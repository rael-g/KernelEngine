#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <kernel_engine/render/core/render_core_export.h>

namespace kernel_engine::render::core
{

struct RenderContext;
class LightingManager;

/**
 * @brief Implements Clustered Forward Rendering data structures and GPU passes.
 */
class KE_RENDER_CORE_API ClusteredForward
{
public:
    ke_result SetupClustered(RenderContext& ctx, render::GpuProgramHandle& out_depth_prog, render::GpuProgramHandle& out_cull_prog);
    ke_result SetClusterConfig(RenderContext& ctx, const ke_cluster_config *config);

    void UpdateClusterBounds(RenderContext& ctx);
    void DispatchLightCull(RenderContext& ctx, const LightingManager& lighting, render::GpuProgramHandle cull_prog);
    void RebuildClusterBuffers(RenderContext& ctx);
    
    void Shutdown(RenderContext& ctx);

    // GPU resources for clustering
    render::GpuUniformHandle cluster_params_uniform = render::kGpuInvalidHandle;

private:
    ke_cluster_config cluster_config_{};
    bool bounds_dirty_ = true;
};

} // namespace kernel_engine::render::core
