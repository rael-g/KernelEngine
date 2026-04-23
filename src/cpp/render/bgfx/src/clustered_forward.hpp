#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <cstdint>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class LightingManager;

/**
 * @brief Manages Clustered Forward shading logic using the HAL.
 */
class KE_RENDER_API ClusteredForward
{
public:
    ke_result SetClusterConfig(RenderContext& ctx, const ke_cluster_config *config);

    ke_result SetupClustered(RenderContext& ctx, 
                             GpuProgramHandle& out_depth_prog, 
                             GpuProgramHandle& out_cull_prog);
    
    void RebuildClusterBuffers(RenderContext& ctx);
    void UpdateClusterBounds(RenderContext& ctx);
    void DispatchLightCull(RenderContext& ctx, 
                           const LightingManager& lighting,
                           GpuProgramHandle cull_program);

    void Shutdown(RenderContext& ctx);

    GpuUniformHandle            cluster_params_u   = kGpuInvalidHandle;
    GpuUniformHandle            cluster_params2_u  = kGpuInvalidHandle;
    GpuDynamicIndexBufferHandle b_point_lights     = kGpuInvalidHandle;
    GpuDynamicIndexBufferHandle b_spot_lights      = kGpuInvalidHandle;

private:
    ke_cluster_config cluster_config_{16, 8, 24, 64, 4096};
    bool bounds_dirty_ = true;

    GpuUniformHandle            compute_view_u_    = kGpuInvalidHandle;
    GpuDynamicIndexBufferHandle b_cluster_bounds_  = kGpuInvalidHandle;
    GpuDynamicIndexBufferHandle b_p_light_indices_ = kGpuInvalidHandle;
    GpuDynamicIndexBufferHandle b_p_light_count_   = kGpuInvalidHandle;
    GpuDynamicIndexBufferHandle b_s_light_indices_ = kGpuInvalidHandle;
    GpuDynamicIndexBufferHandle b_s_light_count_   = kGpuInvalidHandle;
};

} // namespace kernel_engine::render::bgfx
