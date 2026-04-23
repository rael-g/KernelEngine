#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class GeometryManager;

struct ShadowMapEntry
{
    GpuTextureHandle     color_tex = kGpuInvalidHandle;
    GpuTextureHandle     depth_tex = kGpuInvalidHandle;
    GpuFrameBufferHandle fb        = kGpuInvalidHandle;
    uint32_t             width     = 0;
    uint32_t             height    = 0;
    bool                 valid     = false;
};

/**
 * @brief Manages shadow map resources and shadow passes using the HAL.
 */
class KE_RENDER_API ShadowPipeline
{
public:
    ke_result CreateShadowMap(RenderContext& ctx, uint32_t width, uint32_t height, ke_shadow_map_handle *out_handle);
    ke_result DestroyShadowMap(RenderContext& ctx, ke_shadow_map_handle handle);
    ke_result BeginShadowPass(RenderContext& ctx, ke_shadow_map_handle handle, const ke_mat4 *light_view, const ke_mat4 *light_proj);
    ke_result SubmitMeshShadow(RenderContext& ctx, const GeometryManager& geometry, GpuProgramHandle shadow_program, ke_mesh_handle mesh, const ke_mat4 *transform);
    ke_result EndShadowPass(RenderContext& ctx);
    ke_result SetShadowMap(RenderContext& ctx, ke_shadow_map_handle handle);

    void Shutdown();

    GpuTextureHandle GetActiveShadowMapTex() const;

    GpuUniformHandle shadow_map_uniform    = kGpuInvalidHandle;
    GpuUniformHandle light_vp_uniform      = kGpuInvalidHandle;
    GpuUniformHandle shadow_params_uniform = kGpuInvalidHandle;
    uint32_t         active_shadow_handle  = kInvalidShadowHandle;
    float            active_light_vp[16]{};

private:
    std::vector<ShadowMapEntry> shadow_maps_;
};

} // namespace kernel_engine::render::bgfx
