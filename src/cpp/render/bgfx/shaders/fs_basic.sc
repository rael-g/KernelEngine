$input v_color0, v_normal, v_texcoord0, v_worldPos, v_shadowCoord

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor,  0);
SAMPLERCUBE(s_envMap,  1);
SAMPLER2D(s_shadowMap, 2);

uniform vec4 u_color;
uniform vec4 u_lightDir;     // xyz = direction toward light source (world space)
uniform vec4 u_lightColor;   // xyz = color * intensity
uniform vec4 u_ambientColor; // xyz = ambient color (used when IBL is off)
uniform vec4 u_pbrParams;    // x = metallic, y = roughness
uniform vec4 u_cameraPos;    // xyz = camera world position
uniform vec4 u_iblParams;    // x = 1 if IBL active, else 0
uniform vec4 u_shadowParams; // x = 1 if shadow map active, else 0

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

    vec3 N = normalize(v_normal);
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

    // ── Shadow factor ──────────────────────────────────────────────────────────
    float shadow = 1.0;
    if (u_shadowParams.x > 0.5)
        shadow = ComputeShadow(v_shadowCoord);

    gl_FragColor = vec4(ambient + direct * shadow, albedo.w);
}
