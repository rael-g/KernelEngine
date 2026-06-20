#pragma once

#include <kernel_engine/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>


namespace kernel_engine::render::core
{

struct RenderContext;

/**
 * @brief Manages GPU texture resources using the HAL.
 */
class TextureManager
{
public:
    bool CreateTextureRgba(RenderContext& ctx, uint32_t w, uint32_t h, const uint8_t *px, ke_texture_handle *out);
    bool CreateCubemapRgba(RenderContext& ctx, uint32_t s, const uint8_t *d, ke_texture_handle *out);
    bool DestroyTexture(RenderContext& ctx, ke_texture_handle handle);

    bool SubmitSkybox(RenderContext& ctx, ke_texture_handle handle, render::GpuProgramHandle prog, render::GpuVertexBufferHandle vb, render::GpuIndexBufferHandle ib, render::GpuUniformHandle sampler, render::GpuUniformHandle tint);

    void Shutdown();

    render::GpuTextureHandle GetTextureIdx(ke_texture_handle handle) const;

    render::GpuTextureHandle default_2d_tex         = render::kGpuInvalidHandle;
    render::GpuTextureHandle default_cube_tex       = render::kGpuInvalidHandle;
    render::GpuTextureHandle active_env_tex         = render::kGpuInvalidHandle;
    render::GpuUniformHandle sampler_uniform        = render::kGpuInvalidHandle;
    render::GpuUniformHandle ssao_blurred_uniform   = render::kGpuInvalidHandle;
    render::GpuUniformHandle skybox_sampler_uniform = render::kGpuInvalidHandle;
    render::GpuUniformHandle skybox_tint_uniform    = render::kGpuInvalidHandle;
    
    bool has_skybox = false;

private:
    std::vector<render::GpuTextureHandle> textures_;
};

} // namespace kernel_engine::render::core
