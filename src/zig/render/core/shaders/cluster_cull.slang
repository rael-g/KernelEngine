// Cluster light culling — one thread per cluster builds the cluster's view-space
// AABB (inline, from the froxel index + projection) and tests each light's
// bounding sphere against it, writing the per-cluster light index list the
// forward pass reads. Translated from the legacy bgfx cs_light_cull (bounds were
// a precomputed buffer there; here they are derived in-shader). The view is
// left-handed (camera looks +Z), so a point in front has view-space z in
// [near, far] (positive). Froxel grid: numX×numY screen tiles × numZ
// exponential depth slices (Olsson 2012).

struct ClusterParams {
    float4   grid;   // x=numX, y=numY, z=numZ, w=maxLightsPerCluster
    float4   counts; // x=pointCount, y=spotCount
    float4   proj;   // x=tan(fovY/2), y=aspect, z=near, w=far
    float4x4 view;   // world → view
};
[[vk::binding(0, 0)]] ConstantBuffer<ClusterParams> params;

struct PointLight { float4 pos_radius; float4 color_intensity; };
[[vk::binding(1, 0)]] StructuredBuffer<PointLight> point_lights;

struct SpotLight { float4 pos_range; float4 dir_cos_inner; float4 color_intensity; float4 cone; };
[[vk::binding(2, 0)]] StructuredBuffer<SpotLight> spot_lights;

[[vk::binding(3, 0)]] RWStructuredBuffer<uint> point_indices;
[[vk::binding(4, 0)]] RWStructuredBuffer<uint> point_counts;
[[vk::binding(5, 0)]] RWStructuredBuffer<uint> spot_indices;
[[vk::binding(6, 0)]] RWStructuredBuffer<uint> spot_counts;

bool sphere_hits_aabb(float3 center, float radius, float3 amin, float3 amax) {
    float3 closest = max(amin, min(center, amax));
    float3 d = closest - center;
    return dot(d, d) <= radius * radius;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void cs_main(uint3 gid : SV_DispatchThreadID) {
    uint ci = gid.x;
    uint numX = (uint)params.grid.x;
    uint numY = (uint)params.grid.y;
    uint numZ = (uint)params.grid.z;
    uint num_clusters = numX * numY * numZ;
    if (ci >= num_clusters) return;

    uint max_lights = (uint)params.grid.w;

    // Froxel coords from the flat cluster index.
    uint iz = ci / (numX * numY);
    uint iy = (ci % (numX * numY)) / numX;
    uint ix = ci % numX;

    float tan_half = params.proj.x;
    float aspect   = params.proj.y;
    float near     = params.proj.z;
    float far      = params.proj.w;

    // Exponential depth slice + screen tile → NDC. NDC y: +1 = top (framebuffer
    // row 0), matching the forward's tile from SV_Position.y.
    float z_near = near * pow(far / near, (float)iz / (float)numZ);
    float z_far  = near * pow(far / near, (float)(iz + 1u) / (float)numZ);
    float nx0 = (float)ix / (float)numX * 2.0 - 1.0;
    float nx1 = (float)(ix + 1u) / (float)numX * 2.0 - 1.0;
    float ny0 = 1.0 - (float)(iy + 1u) / (float)numY * 2.0;
    float ny1 = 1.0 - (float)iy / (float)numY * 2.0;

    float zs[2] = { z_near, z_far };
    float nxs[2] = { nx0, nx1 };
    float nys[2] = { ny0, ny1 };
    float3 amin = float3(1e30, 1e30, 1e30);
    float3 amax = float3(-1e30, -1e30, -1e30);
    for (int a = 0; a < 2; a++)
    for (int b = 0; b < 2; b++)
    for (int c = 0; c < 2; c++) {
        float z = zs[a];
        float3 v = float3(nxs[b] * z * tan_half * aspect, nys[c] * z * tan_half, z);
        amin = min(amin, v);
        amax = max(amax, v);
    }

    uint point_total = (uint)params.counts.x;
    uint pc = 0u;
    for (uint pi = 0u; pi < point_total && pc < max_lights; pi++) {
        float4 pr = point_lights[pi].pos_radius;
        float3 vp = mul(params.view, float4(pr.xyz, 1.0)).xyz;
        if (sphere_hits_aabb(vp, pr.w, amin, amax)) {
            point_indices[ci * max_lights + pc] = pi;
            pc++;
        }
    }
    point_counts[ci] = pc;

    uint spot_total = (uint)params.counts.y;
    uint sc = 0u;
    for (uint si = 0u; si < spot_total && sc < max_lights; si++) {
        float4 pr = spot_lights[si].pos_range; // xyz = pos, w = range
        float3 vp = mul(params.view, float4(pr.xyz, 1.0)).xyz;
        if (sphere_hits_aabb(vp, pr.w, amin, amax)) {
            spot_indices[ci * max_lights + sc] = si;
            sc++;
        }
    }
    spot_counts[ci] = sc;
}
