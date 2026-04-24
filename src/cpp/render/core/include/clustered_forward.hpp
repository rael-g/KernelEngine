#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class LightingManager;

/**
 * @brief Implementation of Clustered Forward rendering logic.
 * Agnostic of BGFX, uses HAL for compute and buffer updates.
 */
class KE_RENDER_API ClusteredForward
{
public:
    ke_result SetupClustered(RenderContext& ctx, GpuProgramHandle& depth_prog, GpuProgramHandle& cull_prog);
    ke_result SetClusterConfig(RenderContext& ctx, const ke_cluster_config* config);

    void UpdateClusterBounds(RenderContext& ctx);
    void DispatchLightCull(RenderContext& ctx, const LightingManager& lighting, GpuProgramHandle cull_prog);

    void Shutdown(RenderContext& ctx);

    GpuVertexBufferHandle b_point_lights = kGpuInvalidHandle;
    GpuVertexBufferHandle b_spot_lights  = kGpuInvalidHandle;

private:
    void RebuildClusterBuffers(RenderContext& ctx);

    uint32_t cluster_w_ = 16;
    uint32_t cluster_h_ = 9;
    uint32_t cluster_z_ = 24;

    ke_cluster_config cluster_config_{};

    GpuUniformHandle cluster_params_u  = kGpuInvalidHandle;
    GpuUniformHandle cluster_params2_u = kGpuInvalidHandle;
    GpuUniformHandle compute_view_u_   = kGpuInvalidHandle;

    GpuIndexBufferHandle b_cluster_bounds_  = kGpuInvalidHandle;
    GpuIndexBufferHandle b_p_light_indices_ = kGpuInvalidHandle;
    GpuIndexBufferHandle b_p_light_count_   = kGpuInvalidHandle;
    GpuIndexBufferHandle b_s_light_indices_ = kGpuInvalidHandle;
    GpuIndexBufferHandle b_s_light_count_   = kGpuInvalidHandle;

    bool bounds_dirty_ = true;
};

} // namespace kernel_engine::render::bgfx
