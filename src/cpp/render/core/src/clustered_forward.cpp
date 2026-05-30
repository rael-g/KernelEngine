#include "clustered_forward.hpp"
#include <render_logging.hpp>
#include "lighting_manager.hpp"
#include "render_context.hpp"
#include "shader_provider.hpp"
#include "gpu_device.hpp"
#include <cstring>
#include <cmath>
#include <algorithm>
#include <cfloat>
#include <vector>


namespace kernel_engine::render::core
{

ke_result ClusteredForward::SetupClustered(RenderContext& ctx, GpuProgramHandle& out_depth_prog,
                                            GpuProgramHandle& out_cull_prog)
{
    if (!ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "SetupClustered", "GPU device not set");

    if (cluster_config_.grid_x == 0)
        cluster_config_ = kDefaultConfig;

    auto& gpu = *ctx.gpu;
    const uint32_t num_clusters = cluster_config_.grid_x * cluster_config_.grid_y * cluster_config_.grid_z;
    const uint32_t max_lights   = cluster_config_.max_total_lights;
    const uint32_t max_per      = cluster_config_.max_lights_per_cluster;

    // `num` for CreateDynamicIndexBuffer counts 32-bit words (INDEX32 flag is set in the flag combos).
    // vec4 buffers: 4 words per vec4 element. uint buffers: 1 word per uint.
    // Each cluster AABB = 2 vec4: (min.xyz, 0) + (max.xyz, 0)
    b_cluster_bounds_ = gpu.CreateDynamicIndexBuffer(num_clusters * 2 * 4,   kFmtVec4RO);
    // Each point light = 2 vec4: (pos.xyz, radius), (r, g, b, intensity)
    b_point_lights_   = gpu.CreateDynamicIndexBuffer(max_lights * 2 * 4,     kFmtVec4RO);
    // Each spot light = 4 vec4: (pos,range)(dir,inner)(rgb,intensity)(outer,0,0,0)
    b_spot_lights_    = gpu.CreateDynamicIndexBuffer(max_lights * 4 * 4,     kFmtVec4RO);
    // Per-cluster light index lists and counts (uint = 1 word each)
    b_point_indices_  = gpu.CreateDynamicIndexBuffer(num_clusters * max_per, kFmtU32RW);
    b_point_count_    = gpu.CreateDynamicIndexBuffer(num_clusters,            kFmtU32RW);
    b_spot_indices_   = gpu.CreateDynamicIndexBuffer(num_clusters * max_per, kFmtU32RW);
    b_spot_count_     = gpu.CreateDynamicIndexBuffer(num_clusters,            kFmtU32RW);

    if (b_cluster_bounds_ == kGpuInvalidHandle || b_point_lights_  == kGpuInvalidHandle ||
        b_spot_lights_    == kGpuInvalidHandle || b_point_indices_ == kGpuInvalidHandle ||
        b_point_count_    == kGpuInvalidHandle || b_spot_indices_  == kGpuInvalidHandle ||
        b_spot_count_     == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "SetupClustered",
                                 "Failed to create cluster GPU buffers");

    // Count buffers are compute-write (BGFX_BUFFER_COMPUTE_WRITE) — bgfx forbids CPU-side
    // UpdateDynamicIndexBuffer on them. The fragment shader's min(count, maxPer) clamp keeps
    // the loop bounded even if a count slot is read before the first compute dispatch.

    cluster_params_uniform = gpu.CreateUniform("u_clusterParams",   GpuUniformType::Vec4, 1);
    u_cluster_params2_    = gpu.CreateUniform("u_clusterParams2",  GpuUniformType::Vec4, 1);
    u_compute_view_       = gpu.CreateUniform("u_computeView",     GpuUniformType::Mat4, 1);
    u_cluster_viewport_   = gpu.CreateUniform("u_clusterViewport", GpuUniformType::Vec4, 1);

    // Load compute shader and create program
    const GpuMemoryBuffer* mem = ctx.shader_provider
                                     ? ctx.shader_provider->LoadShaderBinary(ctx, "cs_light_cull")
                                     : nullptr;
    if (mem)
    {
        GpuShaderHandle cs = gpu.CreateShader(mem);
        if (cs != kGpuInvalidHandle)
            out_cull_prog = gpu.CreateComputeProgram(cs, true);
    }
    if (out_cull_prog == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "SetupClustered",
                                 "Failed to load cs_light_cull");

    cull_program_ = out_cull_prog; // own a copy so RunCull doesn't need it threaded through callers
    (void)out_depth_prog;          // depth pre-pass deferred to a later phase

    bounds_dirty_ = true;
    return KE_OK;
}

void ClusteredForward::RunCull(RenderContext& ctx, const LightingManager& lighting)
{
    UpdateClusterBounds(ctx);
    DispatchLightCull(ctx, lighting, cull_program_);
}

ke_result ClusteredForward::SetClusterConfig(RenderContext& ctx, const ke_cluster_config* config)
{
    if (!config)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "SetClusterConfig", "Config is null");
    cluster_config_ = *config;
    bounds_dirty_ = true;
    return KE_OK;
}

void ClusteredForward::UpdateClusterBounds(RenderContext& ctx)
{
    if (!bounds_dirty_ || !ctx.gpu) return;
    if (b_cluster_bounds_ == kGpuInvalidHandle) return;

    const uint32_t numX = cluster_config_.grid_x;
    const uint32_t numY = cluster_config_.grid_y;
    const uint32_t numZ = cluster_config_.grid_z;
    const float near_z  = ctx.near_z;
    const float far_z   = ctx.far_z;

    // Projection matrix is column-major: index [0]=P00 (fx), [5]=P11 (fy)
    const float inv_fx    = (ctx.last_proj[0] != 0.f) ? (1.0f / ctx.last_proj[0]) : 1.0f;
    const float inv_fy    = (ctx.last_proj[5] != 0.f) ? (1.0f / ctx.last_proj[5]) : 1.0f;
    const float log_ratio = std::log(far_z / near_z);

    const uint32_t num_clusters = numX * numY * numZ;
    std::vector<float> data(num_clusters * 8, 0.f); // 2 vec4 per cluster

    for (uint32_t iz = 0; iz < numZ; iz++)
    {
        // Exponential Z partition (Olsson 2012) — view-space Z is negative in front of camera
        const float z0 = -near_z * std::exp(log_ratio * (float)iz       / (float)numZ);
        const float z1 = -near_z * std::exp(log_ratio * (float)(iz + 1) / (float)numZ);

        for (uint32_t iy = 0; iy < numY; iy++)
        {
            const float ny0 = 2.0f * (float)iy       / (float)numY - 1.0f;
            const float ny1 = 2.0f * (float)(iy + 1) / (float)numY - 1.0f;

            for (uint32_t ix = 0; ix < numX; ix++)
            {
                const float nx0 = 2.0f * (float)ix       / (float)numX - 1.0f;
                const float nx1 = 2.0f * (float)(ix + 1) / (float)numX - 1.0f;

                float min_x = FLT_MAX,  min_y = FLT_MAX,  min_z = FLT_MAX;
                float max_x = -FLT_MAX, max_y = -FLT_MAX, max_z = -FLT_MAX;

                // AABB from 8 frustum corners (2 z slices × 4 xy tile corners)
                for (float zs : {z0, z1})
                {
                    const float az = std::abs(zs);
                    for (float nx : {nx0, nx1})
                    {
                        for (float ny : {ny0, ny1})
                        {
                            const float vx = nx * az * inv_fx;
                            const float vy = ny * az * inv_fy;
                            min_x = std::min(min_x, vx); max_x = std::max(max_x, vx);
                            min_y = std::min(min_y, vy); max_y = std::max(max_y, vy);
                            min_z = std::min(min_z, zs); max_z = std::max(max_z, zs);
                        }
                    }
                }

                const uint32_t ci   = iz * numY * numX + iy * numX + ix;
                float*         slot = data.data() + ci * 8;
                slot[0] = min_x; slot[1] = min_y; slot[2] = min_z; slot[3] = 0.f;
                slot[4] = max_x; slot[5] = max_y; slot[6] = max_z; slot[7] = 0.f;
            }
        }
    }

    const GpuMemoryBuffer* mem = ctx.gpu->Copy(data.data(), (uint32_t)(data.size() * sizeof(float)));
    if (mem)
        ctx.gpu->UpdateDynamicIndexBuffer(b_cluster_bounds_, 0, mem);

    bounds_dirty_ = false;
}

void ClusteredForward::DispatchLightCull(RenderContext& ctx, const LightingManager& lighting,
                                          GpuProgramHandle cull_prog)
{
    if (cull_prog == kGpuInvalidHandle || !ctx.gpu) return;
    if (b_cluster_bounds_ == kGpuInvalidHandle) return;

    auto& gpu = *ctx.gpu;
    const uint32_t point_count = lighting.GetPointLightCount();
    const uint32_t spot_count  = lighting.GetSpotLightCount();
    const uint32_t max_lights  = cluster_config_.max_total_lights
                                     ? cluster_config_.max_total_lights
                                     : kDefaultConfig.max_total_lights;

    // ── Pack point lights: 2 vec4 each ── (pos.xyz, radius) | (r, g, b, intensity)
    {
        const uint32_t         n   = std::min(point_count, max_lights);
        std::vector<float>     buf(max_lights * 8, 0.f);
        const ke_point_light*  src = lighting.GetPointLightData();
        for (uint32_t i = 0; i < n; i++)
        {
            float* d = buf.data() + i * 8;
            d[0] = src[i].pos_x; d[1] = src[i].pos_y; d[2] = src[i].pos_z; d[3] = src[i].radius;
            d[4] = src[i].r;     d[5] = src[i].g;     d[6] = src[i].b;     d[7] = src[i].intensity;
        }
        const GpuMemoryBuffer* mem = gpu.Copy(buf.data(), (uint32_t)(buf.size() * sizeof(float)));
        if (mem) gpu.UpdateDynamicIndexBuffer(b_point_lights_, 0, mem);
    }

    // ── Pack spot lights: 4 vec4 each ──
    //   (pos.xyz, range) | (dir.xyz, inner_angle) | (r, g, b, intensity) | (outer_angle, 0, 0, 0)
    {
        const uint32_t        n   = std::min(spot_count, max_lights);
        std::vector<float>    buf(max_lights * 16, 0.f);
        const ke_spot_light*  src = lighting.GetSpotLightData();
        for (uint32_t i = 0; i < n; i++)
        {
            float* d = buf.data() + i * 16;
            d[0]  = src[i].pos_x;      d[1]  = src[i].pos_y;  d[2]  = src[i].pos_z;  d[3]  = src[i].range;
            d[4]  = src[i].dir_x;      d[5]  = src[i].dir_y;  d[6]  = src[i].dir_z;  d[7]  = src[i].inner_angle;
            d[8]  = src[i].r;          d[9]  = src[i].g;      d[10] = src[i].b;       d[11] = src[i].intensity;
            d[12] = src[i].outer_angle;
        }
        const GpuMemoryBuffer* mem = gpu.Copy(buf.data(), (uint32_t)(buf.size() * sizeof(float)));
        if (mem) gpu.UpdateDynamicIndexBuffer(b_spot_lights_, 0, mem);
    }

    // ── Uniforms ──────────────────────────────────────────────────────────────
    if (cluster_params_uniform != kGpuInvalidHandle)
    {
        const float p[4] = {
            (float)cluster_config_.grid_x,
            (float)cluster_config_.grid_y,
            (float)cluster_config_.grid_z,
            (float)cluster_config_.max_lights_per_cluster
        };
        gpu.SetUniform(cluster_params_uniform, p, 1);
    }
    if (u_cluster_params2_ != kGpuInvalidHandle)
    {
        const float p2[4] = {(float)point_count, (float)spot_count, 0.f, 0.f};
        gpu.SetUniform(u_cluster_params2_, p2, 1);
    }
    if (u_compute_view_ != kGpuInvalidHandle)
        gpu.SetUniform(u_compute_view_, ctx.last_view, 1);

    // ── Bind compute buffers ──────────────────────────────────────────────────
    gpu.SetBuffer(0, b_cluster_bounds_, GpuAccess::Read);
    gpu.SetBuffer(1, b_point_lights_,   GpuAccess::Read);
    gpu.SetBuffer(2, b_spot_lights_,    GpuAccess::Read);
    gpu.SetBuffer(3, b_point_indices_,  GpuAccess::ReadWrite);
    gpu.SetBuffer(4, b_point_count_,    GpuAccess::ReadWrite);
    gpu.SetBuffer(5, b_spot_indices_,   GpuAccess::ReadWrite);
    gpu.SetBuffer(6, b_spot_count_,     GpuAccess::ReadWrite);

    // ── Dispatch: 1 workgroup per cluster (NUM_THREADS(1,1,1) in shader) ─────
    gpu.Dispatch(kComputeViewId, cull_prog,
                 cluster_config_.grid_x,
                 cluster_config_.grid_y,
                 cluster_config_.grid_z);
}

void ClusteredForward::BindForSceneRead(RenderContext& ctx)
{
    if (!ctx.gpu || b_cluster_bounds_ == kGpuInvalidHandle) return;
    auto& gpu = *ctx.gpu;

    // Uniforms — set every call because bgfx draw state is per-Submit
    if (cluster_params_uniform != kGpuInvalidHandle)
    {
        const float p[4] = {
            (float)cluster_config_.grid_x,
            (float)cluster_config_.grid_y,
            (float)cluster_config_.grid_z,
            (float)cluster_config_.max_lights_per_cluster
        };
        gpu.SetUniform(cluster_params_uniform, p, 1);
    }
    if (u_cluster_viewport_ != kGpuInvalidHandle)
    {
        const float vp[4] = {
            (float)ctx.view_w,
            (float)ctx.view_h,
            ctx.near_z,
            ctx.far_z
        };
        gpu.SetUniform(u_cluster_viewport_, vp, 1);
    }

    // Compute buffers for fragment shader (stage slots match BUFFER_RO in fs_basic.sc)
    gpu.SetBuffer(5,  b_point_lights_,  GpuAccess::Read);
    gpu.SetBuffer(6,  b_spot_lights_,   GpuAccess::Read);
    gpu.SetBuffer(7,  b_point_indices_, GpuAccess::Read);
    gpu.SetBuffer(8,  b_point_count_,   GpuAccess::Read);
    gpu.SetBuffer(9,  b_spot_indices_,  GpuAccess::Read);
    gpu.SetBuffer(10, b_spot_count_,    GpuAccess::Read);
}

void ClusteredForward::RebuildClusterBuffers(RenderContext& ctx)
{
    bounds_dirty_ = true;
    UpdateClusterBounds(ctx);
}

void ClusteredForward::Shutdown(RenderContext& ctx)
{
    if (!ctx.gpu) return;
    auto& gpu = *ctx.gpu;

    auto DestroyDIB = [&](GpuDynamicIndexBufferHandle& h) {
        if (h != kGpuInvalidHandle) { gpu.DestroyDynamicIndexBuffer(h); h = kGpuInvalidHandle; }
    };
    auto DestroyU = [&](GpuUniformHandle& h) {
        if (h != kGpuInvalidHandle) { gpu.DestroyUniform(h); h = kGpuInvalidHandle; }
    };

    DestroyDIB(b_cluster_bounds_);
    DestroyDIB(b_point_lights_);
    DestroyDIB(b_spot_lights_);
    DestroyDIB(b_point_indices_);
    DestroyDIB(b_point_count_);
    DestroyDIB(b_spot_indices_);
    DestroyDIB(b_spot_count_);

    DestroyU(cluster_params_uniform);
    DestroyU(u_cluster_params2_);
    DestroyU(u_compute_view_);
    DestroyU(u_cluster_viewport_);
}

} // namespace kernel_engine::render::core
