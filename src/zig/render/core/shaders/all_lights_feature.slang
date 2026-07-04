// Classic-forward dynamic-light feature component — an ILightIterator
// conformance. forward_lit.slang never imports this file and knows nothing
// about it; only mat_test_flat_classic.slang (the comparison twin of
// mat_test_flat.slang) links it in, in place of ClusteredLights.
//
// Brute-force: every fragment loops the full point/spot light arrays, no
// per-froxel binning and no cull compute dispatch precedes this pass. This is
// the "classic forward" baseline cluster_feature.slang's ClusteredLights is
// meant to outperform at high light counts — comparing the two is the reason
// this file exists.
//
// Resources sit at set 3 like ClusteredLights, but only 3 bindings (the same
// point/spot light storage buffers cullSys already fills, plus a total-count
// uniform) instead of 7 — no index/count-per-cluster buffers, no grid UBO.

import ke;

struct PointLight {
    float4 pos_radius;
    float4 color_intensity;
};

struct SpotLight {
    float4 pos_range;
    float4 dir_cos_inner;
    float4 color_intensity;
    float4 cone;
};

[[vk::binding(0, 3)]] StructuredBuffer<PointLight> point_lights;
[[vk::binding(1, 3)]] StructuredBuffer<SpotLight>  spot_lights;

struct LightCounts {
    uint4 counts; // x=point_count, y=spot_count, z/w unused
};
[[vk::binding(2, 3)]] ConstantBuffer<LightCounts> light_counts;

static const float ALL_PI = 3.14159265359;

float all_distribution_ggx(float3 n, float3 h, float rough) {
    float a = rough * rough;
    float a2 = a * a;
    float ndoth = max(dot(n, h), 0.0);
    float d = ndoth * ndoth * (a2 - 1.0) + 1.0;
    return a2 / max(ALL_PI * d * d, 1e-4);
}
float all_geometry_schlick_ggx(float ndotv, float rough) {
    float r = rough + 1.0;
    float k = (r * r) / 8.0;
    return ndotv / (ndotv * (1.0 - k) + k);
}
float all_geometry_smith(float3 n, float3 v, float3 l, float rough) {
    return all_geometry_schlick_ggx(max(dot(n, v), 0.0), rough) *
           all_geometry_schlick_ggx(max(dot(n, l), 0.0), rough);
}
float3 all_fresnel_schlick(float cos_theta, float3 f0) {
    return f0 + (1.0 - f0) * pow(saturate(1.0 - cos_theta), 5.0);
}
float3 all_pbr_direct(float3 n, float3 v, float3 l, float3 albedo_c, float3 f0,
                       float metallic, float rough, float3 radiance) {
    float ndotl = max(dot(n, l), 0.0);
    if (ndotl <= 0.0) return float3(0.0, 0.0, 0.0);
    float3 h   = normalize(v + l);
    float  ndf = all_distribution_ggx(n, h, rough);
    float  g   = all_geometry_smith(n, v, l, rough);
    float3 f   = all_fresnel_schlick(max(dot(h, v), 0.0), f0);
    float3 spec = (ndf * g * f) / (4.0 * max(dot(n, v), 0.0) * ndotl + 1e-4);
    float3 kd   = (float3(1.0, 1.0, 1.0) - f) * (1.0 - metallic);
    float3 diff = kd * albedo_c / ALL_PI;
    return (diff + spec) * radiance * ndotl;
}

struct AllLights : ILightIterator {
    float3 accumulate(float3 n, float3 v, float3 albedo, float3 f0, float metallic, float rough,
                       float3 worldPos, float2 fragXY, float viewZ) {
        float3 lit = float3(0.0, 0.0, 0.0);

        uint pcount = light_counts.counts.x;
        for (uint i = 0u; i < pcount; i++) {
            float3 to_l   = point_lights[i].pos_radius.xyz - worldPos;
            float  dist   = length(to_l);
            float  radius = point_lights[i].pos_radius.w;
            float3 l      = to_l / max(dist, 1e-4);
            float  att    = clamp(1.0 - dist / max(radius, 1e-4), 0.0, 1.0);
            att *= att;
            float3 radiance = point_lights[i].color_intensity.rgb *
                              point_lights[i].color_intensity.w * att;
            lit += all_pbr_direct(n, v, l, albedo, f0, metallic, rough, radiance);
        }

        uint scount = light_counts.counts.y;
        for (uint sp = 0u; sp < scount; sp++) {
            float3 to_l  = spot_lights[sp].pos_range.xyz - worldPos;
            float  dist  = length(to_l);
            float  range = spot_lights[sp].pos_range.w;
            float3 l     = to_l / max(dist, 1e-4);
            float  datt  = clamp(1.0 - dist / max(range, 1e-4), 0.0, 1.0);
            datt *= datt;
            float3 sdir     = normalize(spot_lights[sp].dir_cos_inner.xyz);
            float  cos_in   = spot_lights[sp].dir_cos_inner.w;
            float  cos_out  = spot_lights[sp].cone.x;
            float  cos_a    = dot(-l, sdir);
            float  catt     = clamp((cos_a - cos_out) / max(cos_in - cos_out, 1e-3), 0.0, 1.0);
            float3 radiance = spot_lights[sp].color_intensity.rgb *
                              spot_lights[sp].color_intensity.w * datt * catt;
            lit += all_pbr_direct(n, v, l, albedo, f0, metallic, rough, radiance);
        }

        return lit;
    }
}
