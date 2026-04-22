#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "InternalTypes.hpp"
#include <cstdint>

namespace kernel_engine::render::bgfx
{

/**
 * @brief Manages Clustered Forward shading logic and light culling.
 */
class KE_RENDER_API ClusteredForward
{
public:
    ke_result SetClusterConfig(const ke_cluster_config *config);

protected:
    virtual ke_result SetupClustered();
    virtual void RebuildClusterBuffers();
    virtual void UpdateClusterBounds();
    virtual void DispatchLightCull();

    ke_cluster_config cluster_config_{16, 8, 24, 64, 4096};
    bool bounds_dirty_ = true;

    uint16_t cluster_params_u_  = kInvalidHandle;
    uint16_t cluster_params2_u_ = kInvalidHandle;
    uint16_t compute_view_u_    = kInvalidHandle;

    uint16_t b_cluster_bounds_  = kInvalidHandle;
    uint16_t b_p_light_indices_ = kInvalidHandle;
    uint16_t b_p_light_count_   = kInvalidHandle;
    uint16_t b_s_light_indices_ = kInvalidHandle;
    uint16_t b_s_light_count_   = kInvalidHandle;
    
    // Structured buffers for lights
    uint16_t b_point_lights_    = kInvalidHandle;
    uint16_t b_spot_lights_     = kInvalidHandle;
};

} // namespace kernel_engine::render::bgfx
