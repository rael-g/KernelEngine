#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class GeometryManager;

struct ShadowMapEntry
{
    GpuFrameBufferHandle fb = kGpuInvalidHandle;
    GpuTextureHandle depth_tex = kGpuInvalidHandle;
    uint32_t w, h;
    bool valid = false;
};

/**
 * @brief Manages shadow mapping passes using the HAL.
 */
class KE_RENDER_API ShadowPipeline
{
public:
    ke_result CreateShadowMap(RenderContext& ctx, uint32_t w, uint32_t h, ke_shadow_map_handle *out);
    ke_result DestroyShadowMap(RenderContext& ctx, ke_shadow_map_handle handle);

    ke_result BeginShadowPass(RenderContext& ctx, ke_shadow_map_handle h, const ke_mat4 *v, const ke_mat4 *p);
    ke_result SubmitMeshShadow(RenderContext& ctx, const GeometryManager& geom, GpuProgramHandle prog, ke_mesh_handle m, const ke_mat4 *t);
    ke_result EndShadowPass(RenderContext& ctx);

    ke_result SetShadowMap(RenderContext& ctx, ke_shadow_map_handle h);

    GpuTextureHandle GetActiveShadowTex() const;

    void Shutdown();

    ke_shadow_map_handle active_shadow_handle = KE_SHADOW_MAP_NONE;

    // Uniforms used by the renderer
    GpuUniformHandle shadow_map_uniform    = kGpuInvalidHandle;
    GpuUniformHandle light_vp_uniform      = kGpuInvalidHandle;
    GpuUniformHandle shadow_params_uniform = kGpuInvalidHandle;

private:
    std::vector<ShadowMapEntry> shadow_maps_;
};

} // namespace kernel_engine::render::bgfx
