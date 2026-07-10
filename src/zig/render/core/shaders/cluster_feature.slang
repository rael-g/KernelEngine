// Clustered dynamic-light hook — a plain function reading neutral-default
// resources. deferred_lighting.slang and transparent_forward.slang both always
// call accumulate_clustered_lights(); when no cull module populates real light
// lists, the point/spot count buffers are bound to a tiny zeroed default, so
// every cluster iterates zero lights and the function returns 0 — the neutral
// element for an additive lighting term. There is no generic conformance to
// select; the hook is realized by which resource is bound, not by which type
// is linked.
//
// Resources stay at set 3 (bindings 0-5, unchanged from before this file
// existed) — a genuinely separate bind-group set, not appended into set 0
// like shadow_feature.slang/ibl_feature.slang. There was room: the C ABI caps
// bind_group_layouts at 4 entries (sets 0-3) and set 3 was already reserved
// solely for this data, so no append-vs-new-set tradeoff applied here.
//
// Self-contained: its own copy of the direct-lighting BRDF (matches
// ke.pbr's pbr_direct exactly — see forward_common.slang / deferred_lighting.slang
// for the shared version). Duplicated rather than shared via import to keep
// this feature decoupled from the pass file, at the small cost of ~20
// duplicated lines.

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
[[vk::binding(2, 3)]] StructuredBuffer<uint>       point_indices;
[[vk::binding(3, 3)]] StructuredBuffer<uint>       point_counts;
[[vk::binding(4, 3)]] StructuredBuffer<uint>       spot_indices;
[[vk::binding(5, 3)]] StructuredBuffer<uint>       spot_counts;

static const float CLUSTER_PI = 3.14159265359;

float cluster_distribution_ggx(float3 n, float3 h, float rough) {
    float a = rough * rough;
    float a2 = a * a;
    float ndoth = max(dot(n, h), 0.0);
    float d = ndoth * ndoth * (a2 - 1.0) + 1.0;
    return a2 / max(CLUSTER_PI * d * d, 1e-4);
}
float cluster_geometry_schlick_ggx(float ndotv, float rough) {
    float r = rough + 1.0;
    float k = (r * r) / 8.0;
    return ndotv / (ndotv * (1.0 - k) + k);
}
float cluster_geometry_smith(float3 n, float3 v, float3 l, float rough) {
    return cluster_geometry_schlick_ggx(max(dot(n, v), 0.0), rough) *
           cluster_geometry_schlick_ggx(max(dot(n, l), 0.0), rough);
}
float3 cluster_fresnel_schlick(float cos_theta, float3 f0) {
    return f0 + (1.0 - f0) * pow(saturate(1.0 - cos_theta), 5.0);
}
float3 cluster_pbr_direct(float3 n, float3 v, float3 l, float3 albedo_c, float3 f0,
                          float metallic, float rough, float3 radiance) {
    float ndotl = max(dot(n, l), 0.0);
    if (ndotl <= 0.0) return float3(0.0, 0.0, 0.0);
    float3 h   = normalize(v + l);
    float  ndf = cluster_distribution_ggx(n, h, rough);
    float  g   = cluster_geometry_smith(n, v, l, rough);
    float3 f   = cluster_fresnel_schlick(max(dot(h, v), 0.0), f0);
    float3 spec = (ndf * g * f) / (4.0 * max(dot(n, v), 0.0) * ndotl + 1e-4);
    float3 kd   = (float3(1.0, 1.0, 1.0) - f) * (1.0 - metallic);
    float3 diff = kd * albedo_c / CLUSTER_PI;
    return (diff + spec) * radiance * ndotl;
}

struct ClusterGrid {
    float4 cluster_grid;     // numX, numY, numZ, maxLightsPerCluster
    float4 cluster_viewport; // screen W, screen H, near, far
};
[[vk::binding(6, 3)]] ConstantBuffer<ClusterGrid> cluster;

uint cluster_index(float2 frag_xy, float view_z) {
    uint numX = (uint)cluster.cluster_grid.x;
    uint numY = (uint)cluster.cluster_grid.y;
    uint numZ = (uint)cluster.cluster_grid.z;
    float near = cluster.cluster_viewport.z;
    float far  = cluster.cluster_viewport.w;
    uint ix = (uint)clamp(frag_xy.x / cluster.cluster_viewport.x * (float)numX, 0.0, (float)(numX - 1u));
    uint iy = (uint)clamp(frag_xy.y / cluster.cluster_viewport.y * (float)numY, 0.0, (float)(numY - 1u));
    float zs = (float)numZ * log(max(view_z, near) / near) / log(far / near);
    uint iz = (uint)clamp(zs, 0.0, (float)(numZ - 1u));
    return iz * numX * numY + iy * numX + ix;
}

float3 accumulate_clustered_lights(float3 n, float3 v, float3 albedo, float3 f0, float metallic, float rough,
                   float3 worldPos, float2 fragXY, float viewZ) {
    uint ci        = cluster_index(fragXY, viewZ);
    uint maxLights = (uint)cluster.cluster_grid.w;
    float3 lit = float3(0.0, 0.0, 0.0);

    uint pcount = point_counts[ci];
    for (uint i = 0u; i < pcount; i++) {
        uint   li     = point_indices[ci * maxLights + i];
        float3 to_l   = point_lights[li].pos_radius.xyz - worldPos;
        float  dist   = length(to_l);
        float  radius = point_lights[li].pos_radius.w;
        float3 l      = to_l / max(dist, 1e-4);
        float  att    = clamp(1.0 - dist / max(radius, 1e-4), 0.0, 1.0);
        att *= att;
        float3 radiance = point_lights[li].color_intensity.rgb *
                          point_lights[li].color_intensity.w * att;
        lit += cluster_pbr_direct(n, v, l, albedo, f0, metallic, rough, radiance);
    }

    uint scount = spot_counts[ci];
    for (uint sp = 0u; sp < scount; sp++) {
        uint   li    = spot_indices[ci * maxLights + sp];
        float3 to_l  = spot_lights[li].pos_range.xyz - worldPos;
        float  dist  = length(to_l);
        float  range = spot_lights[li].pos_range.w;
        float3 l     = to_l / max(dist, 1e-4);
        float  datt  = clamp(1.0 - dist / max(range, 1e-4), 0.0, 1.0);
        datt *= datt;
        float3 sdir     = normalize(spot_lights[li].dir_cos_inner.xyz);
        float  cos_in   = spot_lights[li].dir_cos_inner.w;
        float  cos_out  = spot_lights[li].cone.x;
        float  cos_a    = dot(-l, sdir);
        float  catt     = clamp((cos_a - cos_out) / max(cos_in - cos_out, 1e-3), 0.0, 1.0);
        float3 radiance = spot_lights[li].color_intensity.rgb *
                          spot_lights[li].color_intensity.w * datt * catt;
        lit += cluster_pbr_direct(n, v, l, albedo, f0, metallic, rough, radiance);
    }

    return lit;
}
