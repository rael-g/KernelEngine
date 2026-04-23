#include "clustered_forward.hpp"
#include "render_context.hpp"
#include "lighting_manager.hpp"
#include "shader_provider.hpp"
#include "gpu_device.hpp"
#include <vector>
#include <cmath>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result ClusteredForward::SetupClustered(RenderContext& ctx, 
                                         GpuProgramHandle& out_depth_prog, 
                                         GpuProgramHandle& out_cull_prog)
{
    if (!ctx.gpu || !ctx.shader_provider) return KE_ERROR_RENDER;

    auto load_shader = [&](const char* name) -> GpuShaderHandle {
        const GpuMemoryBuffer* mem = ctx.shader_provider->LoadShaderBinary(ctx, name);
        if (!mem) return kGpuInvalidHandle;
        return ctx.gpu->CreateShader(mem);
    };

    GpuShaderHandle vs_d = load_shader("vs_depth");
    GpuShaderHandle fs_d = load_shader("fs_depth");
    if (vs_d != kGpuInvalidHandle && fs_d != kGpuInvalidHandle)
        out_depth_prog = ctx.gpu->CreateProgram(vs_d, fs_d, true);

    GpuShaderHandle cs_c = load_shader("cs_light_cull");
    if (cs_c != kGpuInvalidHandle)
        out_cull_prog = ctx.gpu->CreateComputeProgram(cs_c, true);

    cluster_params_u  = ctx.gpu->CreateUniform("u_clusterParams",  GpuUniformType::Vec4, 1);
    cluster_params2_u = ctx.gpu->CreateUniform("u_clusterParams2", GpuUniformType::Vec4, 1);
    compute_view_u_   = ctx.gpu->CreateUniform("u_computeView",    GpuUniformType::Mat4, 1);

    RebuildClusterBuffers(ctx);
    return KE_OK;
}

void ClusteredForward::RebuildClusterBuffers(RenderContext& ctx)
{
    if (!ctx.gpu) return;

    auto destroy_buffer = [&](GpuDynamicIndexBufferHandle &h) {
        if (h != kGpuInvalidHandle) ctx.gpu->DestroyDynamicIndexBuffer(h);
        h = kGpuInvalidHandle;
    };

    destroy_buffer(b_cluster_bounds_);
    destroy_buffer(b_point_lights);
    destroy_buffer(b_spot_lights);
    destroy_buffer(b_p_light_indices_);
    destroy_buffer(b_p_light_count_);
    destroy_buffer(b_s_light_indices_);
    destroy_buffer(b_s_light_count_);

    uint32_t numClusters = cluster_config_.grid_x * cluster_config_.grid_y * cluster_config_.grid_z;

    // BGFX_BUFFER_COMPUTE_READ (0x0100)
    b_cluster_bounds_ = ctx.gpu->CreateDynamicIndexBuffer(numClusters * 32 / 2, 0x0100);
    b_point_lights = ctx.gpu->CreateDynamicIndexBuffer(cluster_config_.max_total_lights * 32 / 2, 0x0100);
    b_spot_lights  = ctx.gpu->CreateDynamicIndexBuffer(cluster_config_.max_total_lights * 48 / 2, 0x0100);
    
    // BGFX_BUFFER_COMPUTE_READ_WRITE (0x0300)
    b_p_light_indices_ = ctx.gpu->CreateDynamicIndexBuffer(numClusters * cluster_config_.max_lights_per_cluster * 4 / 2, 0x0300);
    b_s_light_indices_ = ctx.gpu->CreateDynamicIndexBuffer(numClusters * cluster_config_.max_lights_per_cluster * 4 / 2, 0x0300);
    b_p_light_count_ = ctx.gpu->CreateDynamicIndexBuffer(numClusters * 4 / 2, 0x0300);
    b_s_light_count_ = ctx.gpu->CreateDynamicIndexBuffer(numClusters * 4 / 2, 0x0300);

    bounds_dirty_ = true;
}

void ClusteredForward::UpdateClusterBounds(RenderContext& ctx)
{
    if (!bounds_dirty_ || !ctx.gpu) return;

    float nearZ = ctx.near_z;
    float farZ  = ctx.far_z;
    uint32_t numX = cluster_config_.grid_x;
    uint32_t numY = cluster_config_.grid_y;
    uint32_t numZ = cluster_config_.grid_z;

    struct AABB { float min[4]; float max[4]; };
    std::vector<AABB> bounds(numX * numY * numZ);

    float invProj00 = 1.0f / ctx.last_proj[0];
    float invProj11 = 1.0f / ctx.last_proj[5];

    for (uint32_t iz = 0; iz < numZ; ++iz)
    {
        float z0 = nearZ * powf(farZ / nearZ, (float)iz / numZ);
        float z1 = nearZ * powf(farZ / nearZ, (float)(iz + 1) / numZ);
        for (uint32_t iy = 0; iy < numY; ++iy)
        {
            float yNDC0 = (float)iy / numY * 2.0f - 1.0f;
            float yNDC1 = (float)(iy + 1) / numY * 2.0f - 1.0f;
            for (uint32_t ix = 0; ix < numX; ++ix)
            {
                float xNDC0 = (float)ix / numX * 2.0f - 1.0f;
                float xNDC1 = (float)(ix + 1) / numX * 2.0f - 1.0f;
                float vz0 = -z0;
                float vz1 = -z1;
                float x0z0 = xNDC0 * z0 * invProj00;
                float x1z0 = xNDC1 * z0 * invProj00;
                float y0z0 = yNDC0 * z0 * invProj11;
                float y1z0 = yNDC1 * z0 * invProj11;
                float x0z1 = xNDC0 * z1 * invProj00;
                float x1z1 = xNDC1 * z1 * invProj00;
                float y0z1 = yNDC0 * z1 * invProj11;
                float y1z1 = yNDC1 * z1 * invProj11;

                AABB &b = bounds[iz * numX * numY + iy * numX + ix];
                b.min[0] = std::min({x0z0, x1z0, x0z1, x1z1});
                b.min[1] = std::min({y0z0, y1z0, y0z1, y1z1});
                b.min[2] = vz1;
                b.min[3] = 0.0f;
                b.max[0] = std::max({x0z0, x1z0, x0z1, x1z1});
                b.max[1] = std::max({y0z0, y1z0, y0z1, y1z1});
                b.max[2] = vz0;
                b.max[3] = 0.0f;
            }
        }
    }

    ctx.gpu->UpdateDynamicIndexBuffer(b_cluster_bounds_, 0,
                   ctx.gpu->Copy(bounds.data(), (uint32_t)(bounds.size() * sizeof(AABB))));
    bounds_dirty_ = false;
}

void ClusteredForward::DispatchLightCull(RenderContext& ctx, 
                                        const LightingManager& lighting,
                                        GpuProgramHandle cull_program)
{
    if (cull_program == kGpuInvalidHandle || !ctx.gpu) return;

    ctx.gpu->SetUniform(compute_view_u_, ctx.last_view, 1);

    float params[4] = {(float)cluster_config_.grid_x, (float)cluster_config_.grid_y,
                       (float)cluster_config_.grid_z, (float)cluster_config_.max_lights_per_cluster};
    ctx.gpu->SetUniform(cluster_params_u, params, 1);

    float params2[4] = {(float)lighting.GetPointLightCount(), (float)lighting.GetSpotLightCount(), 0.f, 0.f};
    ctx.gpu->SetUniform(cluster_params2_u, params2, 1);

    ctx.gpu->SetBuffer(0, b_cluster_bounds_, GpuAccess::Read);
    ctx.gpu->SetBuffer(1, b_point_lights,   GpuAccess::Read);
    ctx.gpu->SetBuffer(2, b_spot_lights,    GpuAccess::Read);

    ctx.gpu->SetBuffer(3, b_p_light_indices_, GpuAccess::ReadWrite);
    ctx.gpu->SetBuffer(4, b_p_light_count_,   GpuAccess::ReadWrite);
    ctx.gpu->SetBuffer(5, b_s_light_indices_, GpuAccess::ReadWrite);
    ctx.gpu->SetBuffer(6, b_s_light_count_,   GpuAccess::ReadWrite);

    ctx.gpu->Dispatch(kLightCullView, cull_program,
                     (uint16_t)cluster_config_.grid_x, (uint16_t)cluster_config_.grid_y, (uint16_t)cluster_config_.grid_z);
}

ke_result ClusteredForward::SetClusterConfig(RenderContext& ctx, const ke_cluster_config *config)
{
    if (!config) return KE_ERROR_INVALID_ARGUMENT;
    if (config->grid_x == 0 || config->grid_y == 0 || config->grid_z == 0) return KE_ERROR_INVALID_ARGUMENT;
    cluster_config_ = *config;
    RebuildClusterBuffers(ctx);
    return KE_OK;
}

void ClusteredForward::Shutdown(RenderContext& ctx)
{
}

} // namespace kernel_engine::render::bgfx
