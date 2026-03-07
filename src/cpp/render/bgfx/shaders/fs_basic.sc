$input v_color0, v_normal, v_texcoord0, v_worldPos, v_shadowCoord, v_tangent

#include <bgfx_shader.sh>
#include <bgfx_compute.sh>

SAMPLER2D(s_texColor,    0);
SAMPLERCUBE(s_envMap,    1);
SAMPLER2D(s_shadowMap,   2);
SAMPLER2D(s_normalMap,   3);
SAMPLER2D(s_ssaoBlurred, 4);

uniform vec4 u_color;
uniform vec4 u_lightDir;     // xyz = direction toward light source (world space)
uniform vec4 u_lightColor;   // xyz = color * intensity
uniform vec4 u_ambientColor; // xyz = ambient color (used when IBL is off)
uniform vec4 u_pbrParams;    // x = metallic, y = roughness
uniform vec4 u_cameraPos;    // xyz = camera world position
uniform vec4 u_iblParams;    // x = 1 if IBL active, else 0
uniform vec4 u_shadowParams; // x = 1 if shadow map active, else 0
uniform vec4 u_normalParams; // x = 1 if normal map active, else 0
uniform vec4 u_ssaoState;    // x = 1 if SSAO active, yz = texel size (1/w, 1/h)
uniform vec4 u_clusterParams;  // x=numX, y=numY, z=numZ, w=maxLightsPerCluster
uniform vec4 u_clusterParams2; // x=pointLightCount, y=spotLightCount, z=nearZ, w=farZ

BUFFER_RO(b_pointLights,       vec4, 5);
BUFFER_RO(b_spotLights,        vec4, 6);
BUFFER_RO(b_pointLightIndices, uint, 7);
BUFFER_RO(b_pointLightCount,   uint, 8);
BUFFER_RO(b_spotLightIndices,  uint, 9);
BUFFER_RO(b_spotLightCount,    uint, 10);

#define PI 3.14159265358979

float DistributionGGX(vec3 N, vec3 H, float roughness)
{
    float a  = roughness * roughness;
    float a2 = a * a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom  = NdotH2 * (a2 - 1.0) + 1.0;
    return a2 / (PI * denom * denom);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
}

vec3 FresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), 5.0);
}

float ComputeShadow(vec4 shadowCoord)
{
    vec3 coord = shadowCoord.xyz / shadowCoord.w;
    // Convert NDC [-1,1] XY to texture UV [0,1]
    coord.xy = coord.xy * 0.5 + 0.5;
    // Discard if outside shadow frustum
    if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0 ||
        coord.z < 0.0 || coord.z > 1.0)
        return 1.0;
    float occluderDepth = texture2D(s_shadowMap, coord.xy).x;
    float bias = 0.005;
    return (coord.z - bias > occluderDepth) ? 0.3 : 1.0;
}

void main()
{
    float metallic  = u_pbrParams.x;
    float roughness = max(u_pbrParams.y, 0.04);

    vec3 N;
    if (u_normalParams.x > 0.5)
    {
        vec3 Tv = normalize(v_tangent.xyz);
        vec3 Nv = normalize(v_normal);
        vec3 Bv = cross(Nv, Tv) * v_tangent.w;
        vec3 ns = texture2D(s_normalMap, v_texcoord0).xyz * 2.0 - 1.0;
        N = normalize(Tv * ns.x + Bv * ns.y + Nv * ns.z);
    }
    else
    {
        N = normalize(v_normal);
    }
    vec3 V = normalize(u_cameraPos.xyz - v_worldPos);
    vec3 R = reflect(-V, N);

    vec4 texColor = texture2D(s_texColor, v_texcoord0);
    vec4 albedo   = texColor * v_color0 * u_color;

    vec3 F0 = mix(vec3_splat(0.04), albedo.xyz, metallic);

    // ── Directional light (Cook-Torrance GGX) ─────────────────────────────────
    vec3  L     = normalize(u_lightDir.xyz);
    vec3  H     = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);

    float NDF = DistributionGGX(N, H, roughness);
    float G   = GeometrySmith(N, V, L, roughness);
    vec3  F   = FresnelSchlick(max(dot(H, V), 0.0), F0);

    vec3 kS = F;
    vec3 kD = (vec3_splat(1.0) - kS) * (1.0 - metallic);

    vec3 numerator    = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001;
    vec3 specular     = numerator / denominator;

    vec3 direct = (kD * albedo.xyz / PI + specular) * u_lightColor.xyz * NdotL;

    // ── Clustered Forward Shading ──────────────────────────────────────────────
    float nearZ = u_clusterParams2.z;
    float farZ  = u_clusterParams2.w;
    float viewZ = (u_view[0].z * v_worldPos.x + u_view[1].z * v_worldPos.y + u_view[2].z * v_worldPos.z + u_view[3].z);
    viewZ = -viewZ; // positive Z is forward in view space

    uint numX = uint(u_clusterParams.x);
    uint numY = uint(u_clusterParams.y);
    uint numZ = uint(u_clusterParams.z);
    uint maxLights = uint(u_clusterParams.w);

    uint ix = uint(gl_FragCoord.x / (u_viewRect[2] / float(numX)));
    uint iy = uint(gl_FragCoord.y / (u_viewRect[3] / float(numY)));
    uint iz = uint(clamp(log(viewZ / nearZ) / log(farZ / nearZ) * float(numZ), 0.0, float(numZ - 1)));

    uint clusterIndex = iz * (numX * numY) + iy * numX + ix;

    // ── Point lights ───────────────────────────────────────────────────────────
    uint pCount = b_pointLightCount[clusterIndex];
    for (uint i = 0; i < pCount; ++i)
    {
        uint pi = b_pointLightIndices[clusterIndex * maxLights + i];
        vec4 pos_r = b_pointLights[pi * 2u];
        vec4 color = b_pointLights[pi * 2u + 1u];

        vec3  Lp   = pos_r.xyz - v_worldPos;
        float dist = length(Lp);
        float rad  = pos_r.w;
        float t    = clamp(1.0 - (dist / rad) * (dist / rad), 0.0, 1.0);
        float att  = t * t;
        vec3  Ldir = normalize(Lp);
        vec3  Hp   = normalize(V + Ldir);
        float NdotLp = max(dot(N, Ldir), 0.0);
        float NDFp = DistributionGGX(N, Hp, roughness);
        float Gp   = GeometrySmith(N, V, Ldir, roughness);
        vec3  Fp   = FresnelSchlick(max(dot(Hp, V), 0.0), F0);
        vec3  kSp  = Fp;
        vec3  kDp  = (vec3_splat(1.0) - kSp) * (1.0 - metallic);
        vec3  specP = (NDFp * Gp * Fp) / (4.0 * max(dot(N, V), 0.0) * NdotLp + 0.0001);
        direct += (kDp * albedo.xyz / PI + specP) * color.xyz * NdotLp * att;
    }

    // ── Spot lights ────────────────────────────────────────────────────────────
    uint sCount = b_spotLightCount[clusterIndex];
    for (uint j = 0; j < sCount; ++j)
    {
        uint si = b_spotLightIndices[clusterIndex * maxLights + j];
        vec4 pos_r      = b_spotLights[si * 3u];
        vec4 dir_cosI   = b_spotLights[si * 3u + 1u];
        vec4 color_cosO = b_spotLights[si * 3u + 2u];

        vec3  Ls    = pos_r.xyz - v_worldPos;
        float distS = length(Ls);
        float rng   = pos_r.w;
        float ts    = clamp(1.0 - (distS / rng) * (distS / rng), 0.0, 1.0);
        float attS  = ts * ts;
        vec3  Ldir  = normalize(Ls);
        vec3  sDir  = normalize(dir_cosI.xyz);
        float cosI  = dir_cosI.w;
        float cosO  = color_cosO.w;
        float cosA  = dot(-Ldir, sDir);
        float spotF = clamp((cosA - cosO) / max(cosI - cosO, 0.0001), 0.0, 1.0);
        attS *= spotF * spotF;
        vec3  Hs    = normalize(V + Ldir);
        float NdotLs = max(dot(N, Ldir), 0.0);
        float NDFs = DistributionGGX(N, Hs, roughness);
        float Gs   = GeometrySmith(N, V, Ldir, roughness);
        vec3  Fs   = FresnelSchlick(max(dot(Hs, V), 0.0), F0);
        vec3  kSs  = Fs;
        vec3  kDs  = (vec3_splat(1.0) - kSs) * (1.0 - metallic);
        vec3  specS = (NDFs * Gs * Fs) / (4.0 * max(dot(N, V), 0.0) * NdotLs + 0.0001);
        direct += (kDs * albedo.xyz / PI + specS) * color_cosO.xyz * NdotLs * attS;
    }

    // ── Ambient: IBL or constant ───────────────────────────────────────────────
    vec3 ambient;
    if (u_iblParams.x > 0.5)
    {
        // Diffuse IBL: sample env in normal direction (approximates irradiance)
        vec3 ibl_diff = textureCube(s_envMap, N).xyz;

        // Specular IBL: sample env in reflection direction
        vec3 ibl_spec = textureCube(s_envMap, R).xyz;

        // Per-channel Fresnel at grazing angle for IBL split-sum approximation
        vec3 F_ibl  = FresnelSchlick(max(dot(N, V), 0.0), F0);
        vec3 kD_ibl = (vec3_splat(1.0) - F_ibl) * (1.0 - metallic);

        ambient = kD_ibl * ibl_diff * albedo.xyz + ibl_spec * F_ibl;
    }
    else
    {
        ambient = u_ambientColor.xyz * albedo.xyz;
    }

    // ── SSAO ambient occlusion ─────────────────────────────────────────────────
    if (u_ssaoState.x > 0.5)
    {
        vec2 screenUV = gl_FragCoord.xy * u_ssaoState.yz;
        float ao = texture2D(s_ssaoBlurred, screenUV).r;
        ambient *= ao;
    }

    // ── Shadow factor ──────────────────────────────────────────────────────────
    float shadow = 1.0;
    if (u_shadowParams.x > 0.5)
        shadow = ComputeShadow(v_shadowCoord);

    gl_FragColor = vec4(ambient + direct * shadow, albedo.w);
}
