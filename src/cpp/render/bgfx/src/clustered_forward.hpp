#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "internal_types.hpp"
#include <cstdint>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class LightingManager;

/**
 * @brief Manages Clustered Forward shading logic and light culling.
 */
class KE_RENDER_API ClusteredForward
{
public:
    ke_result SetClusterConfig(RenderContext& ctx, const ke_cluster_config *config);

    ke_result SetupClustered(RenderContext& ctx, 
                             uint16_t& out_depth_prog, 
                             uint16_t& out_cull_prog);
    
    void RebuildClusterBuffers(RenderContext& ctx);
    void UpdateClusterBounds(RenderContext& ctx);
    void DispatchLightCull(RenderContext& ctx, 
                           const LightingManager& lighting,
                           uint16_t cull_program);

    void Shutdown(RenderContext& ctx);

    uint16_t cluster_params_u   = kInvalidHandle;
    uint16_t cluster_params2_u  = kInvalidHandle;
    uint16_t b_point_lights     = kInvalidHandle;
    uint16_t b_spot_lights      = kInvalidHandle;

private:
    ke_cluster_config cluster_config_{16, 8, 24, 64, 4096};
    bool bounds_dirty_ = true;

    uint16_t compute_view_u_    = kInvalidHandle;
    uint16_t b_cluster_bounds_  = kInvalidHandle;
    uint16_t b_p_light_indices_ = kInvalidHandle;
    uint16_t b_p_light_count_   = kInvalidHandle;
    uint16_t b_s_light_indices_ = kInvalidHandle;
    uint16_t b_s_light_count_   = kInvalidHandle;
};

} // namespace kernel_engine::render::bgfx
