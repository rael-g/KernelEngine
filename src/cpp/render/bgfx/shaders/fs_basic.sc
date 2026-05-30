$input v_normal, v_texcoord0, v_worldPos, v_shadowCoord, v_tangent

#include <bgfx_compute.sh>

SAMPLER2D(s_texColor,    0);
SAMPLERCUBE(s_envMap,    1);
SAMPLER2D(s_shadowMap,   2);
SAMPLER2D(s_normalMap,   3);
SAMPLER2D(s_ssaoBlurred, 4);

// Cluster light data (read-only, populated by cs_light_cull each frame)
// Point lights: 2 vec4 each — (pos.xyz, radius) | (r, g, b, intensity)
BUFFER_RO(b_pointLightsFS,     vec4, 5);
// Spot lights: 3 vec4 each — (pos.xyz, range) | (dir.xyz, inner_angle_rad) | (r, g, b, intensity)
BUFFER_RO(b_spotLightsFS,      vec4, 6);
// Per-cluster index lists and counts (output of cs_light_cull)
BUFFER_RO(b_pointLightIndices, uint, 7);
BUFFER_RO(b_pointLightCount,   uint, 8);
BUFFER_RO(b_spotLightIndices,  uint, 9);
BUFFER_RO(b_spotLightCount,    uint, 10);

uniform vec4 u_color;
uniform vec4 u_lightDir;
uniform vec4 u_lightColor;
uniform vec4 u_ambientColor;
uniform vec4 u_pbrParams;
uniform vec4 u_cameraPos;
uniform vec4 u_iblParams;
uniform vec4 u_shadowParams;
uniform vec4 u_normalParams;
uniform vec4 u_ssaoState;
uniform vec4 u_clusterParams;   // x=numX, y=numY, z=numZ, w=maxLightsPerCluster
uniform vec4 u_clusterParams2;  // x=pointLightCount, y=spotLightCount (unused here, kept for parity)
uniform vec4 u_clusterViewport; // x=viewW, y=viewH, z=near, w=far
uniform vec4 u_lightCounts;     // x=point (brute-force path, kept for fallback), y=spot

uniform vec4 u_pointLights[128];
uniform vec4 u_spotLights[192];

#define PI 3.14159265358979

float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    return a2 / (PI * pow(NdotH * NdotH * (a2 - 1.0) + 1.0, 2.0));
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    return GeometrySchlickGGX(max(dot(N, V), 0.0), roughness) *
           GeometrySchlickGGX(max(dot(N, L), 0.0), roughness);
}

vec3 FresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), 5.0);
}

// Cook-Torrance PBR contribution of a single light with the given incoming radiance.
vec3 PbrDirect(vec3 N, vec3 V, vec3 L, vec3 albedo, vec3 F0, float metallic, float roughness, vec3 radiance) {
    float NdotL = max(dot(N, L), 0.0);
    if (NdotL <= 0.0) return vec3_splat(0.0);
    vec3 H = normalize(V + L);
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
    vec3 spec = (DistributionGGX(N, H, roughness) * GeometrySmith(N, V, L, roughness) * F)
              / (4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001);
    vec3 diff = (vec3_splat(1.0) - F) * (1.0 - metallic) * albedo / PI;
    return (diff + spec) * radiance * NdotL;
}

float ComputeShadow(vec4 shadowCoord) {
    vec3 coord = shadowCoord.xyz / shadowCoord.w;
    coord.x = coord.x * 0.5 + 0.5;
    coord.y = -coord.y * 0.5 + 0.5;
    if (any(lessThan(coord, vec3_splat(0.0))) || any(greaterThan(coord, vec3_splat(1.0)))) return 1.0;
    return (coord.z - 0.005 > texture2D(s_shadowMap, coord.xy).x) ? 0.3 : 1.0;
}

// Returns the flat cluster index for this fragment.
// fragCoord = gl_FragCoord (passed from main because bgfx restricts built-ins to main scope).
// Vulkan NDC depth is [0,1]; z_view is negative (right-hand camera).
uint ComputeClusterIndex(vec4 fragCoord) {
    float numX = u_clusterParams.x;
    float numY = u_clusterParams.y;
    float numZ = u_clusterParams.z;
    float near  = u_clusterViewport.z;
    float far   = u_clusterViewport.w;

    float zNdc  = fragCoord.z;
    float zView = -(near * far) / (far - zNdc * (far - near));

    // Exponential slice matching UpdateClusterBounds (Olsson 2012)
    int iz = int(numZ * log(-zView / near) / log(far / near));
    iz = clamp(iz, 0, int(numZ) - 1);

    int ix = int(fragCoord.x / u_clusterViewport.x * numX);
    // gl_FragCoord.y here is bottom-origin (the scene renders to a Y-flipped target under Vulkan),
    // while the cluster AABBs are built top-origin in UpdateClusterBounds. Flip Y so the fragment's
    // tile matches the cluster the cull placed the light in. Without this, lighting is vertically
    // mirrored — masked by symmetric light layouts except at the screen corners.
    int iy = int((1.0 - fragCoord.y / u_clusterViewport.y) * numY);
    ix = clamp(ix, 0, int(numX) - 1);
    iy = clamp(iy, 0, int(numY) - 1);

    return uint(iz) * uint(numX) * uint(numY)
         + uint(iy) * uint(numX)
         + uint(ix);
}

void main() {
    float metallic = u_pbrParams.x;
    float roughness = max(u_pbrParams.y, 0.04);
    vec3 V = normalize(u_cameraPos.xyz - v_worldPos);

    vec3 N;
    if (u_normalParams.x > 0.5) {
        vec3 Tv = normalize(v_tangent.xyz);
        vec3 Nv = normalize(v_normal);
        vec3 Bv = cross(Nv, Tv) * v_tangent.w;
        vec3 ns = texture2D(s_normalMap, v_texcoord0).xyz * 2.0 - 1.0;
        N = normalize(Tv * ns.x + Bv * ns.y + Nv * ns.z);
    } else {
        N = normalize(v_normal);
    }

    vec3 R = reflect(-V, N);

    vec4 texColor = texture2D(s_texColor, v_texcoord0);
    vec4 albedo   = texColor * u_color;
    vec3 F0 = mix(vec3_splat(0.04), albedo.xyz, metallic);

    // ── Directional ──
    vec3 L = normalize(u_lightDir.xyz);
    vec3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
    vec3 spec = (DistributionGGX(N, H, roughness) * GeometrySmith(N, V, L, roughness) * F) / (4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001);
    vec3 direct = ((vec3_splat(1.0) - F) * (1.0 - metallic) * albedo.xyz / PI + spec) * u_lightColor.xyz * NdotL;

    // ── Ambient (IBL) ──
    vec3 ambient;
    if (u_iblParams.x > 0.5) {
        vec3 irradiance = textureCube(s_envMap, N).xyz;
        vec3 radiance = textureCube(s_envMap, R).xyz;
        vec3 F_ibl = FresnelSchlick(max(dot(N, V), 0.0), F0);
        ambient = ((vec3_splat(1.0) - F_ibl) * (1.0 - metallic) * irradiance * albedo.xyz) + (radiance * F_ibl);
    } else {
        ambient = u_ambientColor.xyz * albedo.xyz;
    }

    if (u_ssaoState.x > 0.5) ambient *= texture2D(s_ssaoBlurred, gl_FragCoord.xy * u_ssaoState.yz).r;
    if (u_shadowParams.x > 0.5) direct *= ComputeShadow(v_shadowCoord);

    // ── Clustered point + spot lights ────────────────────────────────────────
    vec3 dynamicLight = vec3_splat(0.0);
    uint maxPer = uint(u_clusterParams.w);
    uint ci = ComputeClusterIndex(gl_FragCoord);

    // Point lights — clamp count defensively against uninitialised buffer data
    uint pCount = min(b_pointLightCount[ci], maxPer);
    for (uint pi = 0u; pi < pCount; pi++) {
        uint li = b_pointLightIndices[ci * maxPer + pi];
        vec4 pa = b_pointLightsFS[li * 2u];      // pos.xyz, radius
        vec4 pb = b_pointLightsFS[li * 2u + 1u]; // r, g, b, intensity
        vec3 toL = pa.xyz - v_worldPos;
        float dist = length(toL);
        vec3 Lp = toL / max(dist, 0.0001);
        float att = clamp(1.0 - dist / max(pa.w, 0.0001), 0.0, 1.0);
        att *= att;
        dynamicLight += PbrDirect(N, V, Lp, albedo.xyz, F0, metallic, roughness, pb.xyz * pb.w * att);
    }

    // Spot lights (4 vec4: pos/range | dir/innerAngle | rgb/intensity | outerAngle)
    uint sCount = min(b_spotLightCount[ci], maxPer);
    for (uint si = 0u; si < sCount; si++) {
        uint li = b_spotLightIndices[ci * maxPer + si];
        vec4 sa = b_spotLightsFS[li * 4u];      // pos.xyz, range
        vec4 sb = b_spotLightsFS[li * 4u + 1u]; // dir.xyz, inner_angle_rad
        vec4 sc = b_spotLightsFS[li * 4u + 2u]; // r, g, b, intensity
        vec4 sd = b_spotLightsFS[li * 4u + 3u]; // outer_angle_rad
        vec3 toL = sa.xyz - v_worldPos;
        float dist = length(toL);
        vec3 Ls = toL / max(dist, 0.0001);
        float datt = clamp(1.0 - dist / max(sa.w, 0.0001), 0.0, 1.0);
        datt *= datt;
        float cosInner = cos(sb.w);
        float cosOuter = cos(sd.x);
        float cosA = dot(-Ls, normalize(sb.xyz));
        float catt = clamp((cosA - cosOuter) / max(cosInner - cosOuter, 0.001), 0.0, 1.0);
        dynamicLight += PbrDirect(N, V, Ls, albedo.xyz, F0, metallic, roughness, sc.xyz * sc.w * datt * catt);
    }

    gl_FragColor = vec4(ambient + direct + dynamicLight, albedo.w);
}
