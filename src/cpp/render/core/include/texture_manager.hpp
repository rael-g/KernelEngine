#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;

/**
 * @brief Manages GPU texture resources using the HAL.
 */
class KE_RENDER_API TextureManager
{
public:
    ke_result CreateTextureRgba(RenderContext& ctx, uint32_t w, uint32_t h, const uint8_t *px, ke_texture_handle *out);
    ke_result CreateCubemapRgba(RenderContext& ctx, uint32_t s, const uint8_t *d, ke_texture_handle *out);
    ke_result DestroyTexture(RenderContext& ctx, ke_texture_handle handle);

    ke_result SubmitSkybox(RenderContext& ctx, ke_texture_handle handle, GpuProgramHandle prog, GpuVertexBufferHandle vb, GpuIndexBufferHandle ib, GpuUniformHandle sampler, GpuUniformHandle tint);

    void Shutdown();

    GpuTextureHandle GetTextureIdx(ke_texture_handle handle) const;

    GpuTextureHandle default_2d_tex         = kGpuInvalidHandle;
    GpuTextureHandle default_cube_tex       = kGpuInvalidHandle;
    GpuTextureHandle active_env_tex         = kGpuInvalidHandle;
    GpuUniformHandle sampler_uniform        = kGpuInvalidHandle;
    GpuUniformHandle ssao_blurred_uniform   = kGpuInvalidHandle;
    GpuUniformHandle skybox_sampler_uniform = kGpuInvalidHandle;
    GpuUniformHandle skybox_tint_uniform    = kGpuInvalidHandle;
    
    bool has_skybox = false;

private:
    std::vector<GpuTextureHandle> textures_;
};

} // namespace kernel_engine::render::bgfx
