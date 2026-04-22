#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "InternalTypes.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct ShadowMapEntry
{
    uint16_t color_tex = kInvalidHandle;
    uint16_t depth_tex = kInvalidHandle;
    uint16_t fb        = kInvalidHandle;
    uint32_t width     = 0;
    uint32_t height    = 0;
    bool valid         = false;
};

/**
 * @brief Manages shadow map resources and shadow passes.
 */
class KE_RENDER_API ShadowPipeline
{
public:
    ke_result CreateShadowMap(uint32_t width, uint32_t height, ke_shadow_map_handle *out_handle);
    ke_result DestroyShadowMap(ke_shadow_map_handle handle);
    ke_result BeginShadowPass(ke_shadow_map_handle handle, const ke_mat4 *light_view, const ke_mat4 *light_proj);
    ke_result SubmitMeshShadow(ke_mesh_handle mesh, const ke_mat4 *transform);
    ke_result EndShadowPass();
    ke_result SetShadowMap(ke_shadow_map_handle handle);

protected:
    std::vector<ShadowMapEntry> shadow_maps_;
    uint32_t active_shadow_handle_ = kInvalidShadowHandle;
    float    active_light_vp_[16]{};

    uint16_t shadow_map_uniform_    = kInvalidHandle;
    uint16_t light_vp_uniform_      = kInvalidHandle;
    uint16_t shadow_params_uniform_ = kInvalidHandle;
};

} // namespace kernel_engine::render::bgfx
