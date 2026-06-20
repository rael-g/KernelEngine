#pragma once

#include <kernel_engine/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"

namespace kernel_engine::render::core
{

struct RenderContext;
class LightingManager;

/**
 * @brief Implements Clustered Forward Rendering data structures and GPU passes.
 */
class ClusteredForward
{
public:
    bool SetupClustered(RenderContext& ctx, render::GpuProgramHandle& out_depth_prog, render::GpuProgramHandle& out_cull_prog);
    bool SetClusterConfig(RenderContext& ctx, const ke_cluster_config *config);

    void UpdateClusterBounds(RenderContext& ctx);
    void DispatchLightCull(RenderContext& ctx, const LightingManager& lighting, render::GpuProgramHandle cull_prog);
    void RebuildClusterBuffers(RenderContext& ctx);

    /// Update bounds + dispatch the light cull using the internally-owned compute program.
    /// Must be submitted BEFORE the scene draw pass (compute on view 0 → scene on view 1) so
    /// bgfx inserts the compute-write → fragment-read barrier in the correct order.
    void RunCull(RenderContext& ctx, const LightingManager& lighting);

    /// Bind cluster buffers + uniforms for the scene draw pass.
    /// Must be called before each scene draw Submit (SetBuffer state is per-draw in bgfx).
    void BindForSceneRead(RenderContext& ctx);

    void Shutdown(RenderContext& ctx);

    // GPU resources for clustering
    render::GpuUniformHandle cluster_params_uniform = render::kGpuInvalidHandle;

private:
    // View ID for the light-cull compute dispatch. bgfx executes views in id order, so this must
    // sort BEFORE the scene pass (ViewId::Scene = 1) — the scene reads the buffers this writes.
    // A high id (after the backbuffer passes) both lagged a frame and corrupted the swapchain
    // present semaphore (vkAcquireNextImageKHR pending-op error → black screen). View 0 runs first;
    // compute ignores the shadow framebuffer bound to view 0, so sharing the id is harmless.
    // TODO(F.RC2 cleanup): give the cull its own dedicated view via a pipeline renumber.
    static constexpr uint16_t kComputeViewId = 0;

    // bgfx compute buffer flag combos (see bgfx/defines.h for bit layout).
    // INDEX32 (0x1000) makes each buffer element 4 bytes; createDynamicIndexBuffer's `num`
    // must therefore be the count of 32-bit words. Without it bgfx allocates 16-bit indices
    // (2 bytes/elem) and the float/uint upload truncates.
    static constexpr uint16_t kFmtVec4RO = 0x0009 | 0x0030 | 0x0100 | 0x1000; // 32X4 | FLOAT | READ | INDEX32
    static constexpr uint16_t kFmtU32RW  = 0x0007 | 0x0020 | 0x0300 | 0x1000; // 32X1 | UINT  | RW   | INDEX32

    static constexpr ke_cluster_config kDefaultConfig = {16, 8, 24, 256, 512};

    render::GpuDynamicIndexBufferHandle b_cluster_bounds_ = render::kGpuInvalidHandle;
    render::GpuDynamicIndexBufferHandle b_point_lights_   = render::kGpuInvalidHandle;
    render::GpuDynamicIndexBufferHandle b_spot_lights_    = render::kGpuInvalidHandle;
    render::GpuDynamicIndexBufferHandle b_point_indices_  = render::kGpuInvalidHandle;
    render::GpuDynamicIndexBufferHandle b_point_count_    = render::kGpuInvalidHandle;
    render::GpuDynamicIndexBufferHandle b_spot_indices_   = render::kGpuInvalidHandle;
    render::GpuDynamicIndexBufferHandle b_spot_count_     = render::kGpuInvalidHandle;

    render::GpuUniformHandle u_cluster_params2_  = render::kGpuInvalidHandle;
    render::GpuUniformHandle u_compute_view_     = render::kGpuInvalidHandle;
    render::GpuUniformHandle u_cluster_viewport_ = render::kGpuInvalidHandle;

    render::GpuProgramHandle cull_program_ = render::kGpuInvalidHandle;

    ke_cluster_config cluster_config_{};
    bool bounds_dirty_ = true;
};

} // namespace kernel_engine::render::core
