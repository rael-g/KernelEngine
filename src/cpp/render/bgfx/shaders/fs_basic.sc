$input v_normal, v_texcoord0, v_worldPos, v_shadowCoord, v_tangent

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor,    0);
SAMPLERCUBE(s_envMap,    1);
SAMPLER2D(s_shadowMap,   2);
SAMPLER2D(s_normalMap,   3);
SAMPLER2D(s_ssaoBlurred, 4);

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
uniform vec4 u_clusterParams2;
uniform vec4 u_lightCounts; // x = point light count, y = spot light count

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

    // ── Point + spot lights (forward, unshadowed) ──
    vec3 dynamicLight = vec3_splat(0.0);

    int pointCount = int(u_lightCounts.x);
    for (int pi = 0; pi < pointCount; pi++) {
        vec4 pa = u_pointLights[pi * 2 + 0];   // pos.xyz, radius
        vec4 pb = u_pointLights[pi * 2 + 1];   // color.rgb, intensity
        vec3 toL = pa.xyz - v_worldPos;
        float dist = length(toL);
        vec3 Lp = toL / max(dist, 0.0001);
        float att = clamp(1.0 - dist / max(pa.w, 0.0001), 0.0, 1.0);
        att *= att;
        dynamicLight += PbrDirect(N, V, Lp, albedo.xyz, F0, metallic, roughness, pb.xyz * pb.w * att);
    }

    int spotCount = int(u_lightCounts.y);
    for (int si = 0; si < spotCount; si++) {
        vec4 sa = u_spotLights[si * 4 + 0];    // pos.xyz, range
        vec4 sb = u_spotLights[si * 4 + 1];    // dir.xyz, cos(inner)
        vec4 sc = u_spotLights[si * 4 + 2];    // color.rgb, intensity
        float cosOuter = u_spotLights[si * 4 + 3].x;
        vec3 toL = sa.xyz - v_worldPos;
        float dist = length(toL);
        vec3 Ls = toL / max(dist, 0.0001);
        float datt = clamp(1.0 - dist / max(sa.w, 0.0001), 0.0, 1.0);
        datt *= datt;
        float cosA = dot(-Ls, normalize(sb.xyz));            // fragment vs cone axis
        float catt = clamp((cosA - cosOuter) / max(sb.w - cosOuter, 0.0001), 0.0, 1.0);
        dynamicLight += PbrDirect(N, V, Ls, albedo.xyz, F0, metallic, roughness, sc.xyz * sc.w * datt * catt);
    }

    gl_FragColor = vec4(ambient + direct + dynamicLight, albedo.w);
}
