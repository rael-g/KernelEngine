#pragma once

#include <kernel_engine/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>


namespace kernel_engine::render::core
{

struct RenderContext;
class GeometryManager;

struct ShadowMapEntry
{
    render::GpuFrameBufferHandle fb = render::kGpuInvalidHandle;
    render::GpuTextureHandle     depth_tex = render::kGpuInvalidHandle;
    uint32_t w, h;
    bool valid = false;
};

/**
 * @brief Manages shadow mapping passes and GPU resources.
 */
class ShadowPipeline
{
public:
    ke_result CreateShadowMap(RenderContext& ctx, uint32_t w, uint32_t h, ke_shadow_map_handle *out);
    ke_result DestroyShadowMap(RenderContext& ctx, ke_shadow_map_handle handle);

    ke_result BeginShadowPass(RenderContext& ctx, ke_shadow_map_handle h, const ke_mat4 *v, const ke_mat4 *p);
    ke_result SubmitMeshShadow(RenderContext& ctx, const GeometryManager& geom, render::GpuProgramHandle prog, ke_mesh_handle m, const ke_mat4 *t);
    ke_result EndShadowPass(RenderContext& ctx);

    ke_result SetShadowMap(RenderContext& ctx, ke_shadow_map_handle h);

    render::GpuTextureHandle GetActiveShadowTex() const;

    void Shutdown();

    ke_shadow_map_handle active_shadow_handle = KE_SHADOW_MAP_NONE;

    // Uniforms used by the renderer
    render::GpuUniformHandle shadow_map_uniform    = render::kGpuInvalidHandle;
    render::GpuUniformHandle light_vp_uniform      = render::kGpuInvalidHandle;
    render::GpuUniformHandle shadow_params_uniform = render::kGpuInvalidHandle;

private:
    std::vector<ShadowMapEntry> shadow_maps_;
};

} // namespace kernel_engine::render::core
