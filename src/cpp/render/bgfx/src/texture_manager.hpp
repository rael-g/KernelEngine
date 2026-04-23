#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;

struct TextureEntry
{
    GpuTextureHandle idx = kGpuInvalidHandle;
    bool valid = false;
};

/**
 * @brief Manages GPU textures and cubemaps using the HAL.
 */
class KE_RENDER_API TextureManager
{
public:
    ke_result CreateTextureRgba(RenderContext& ctx, uint32_t width, uint32_t height, const uint8_t *pixels,
                                ke_texture_handle *out_handle);
    ke_result DestroyTexture(RenderContext& ctx, ke_texture_handle handle);
    ke_result CreateCubemapRgba(RenderContext& ctx, uint32_t size, const uint8_t *data, ke_texture_handle *out_handle);
    
    ke_result SubmitSkybox(RenderContext& ctx, 
                           ke_texture_handle cubemap_handle,
                           GpuProgramHandle skybox_program,
                           GpuVertexBufferHandle skybox_vb,
                           GpuIndexBufferHandle skybox_ib,
                           GpuUniformHandle skybox_sampler,
                           GpuUniformHandle skybox_tint);

    void Shutdown();

    GpuTextureHandle GetTextureIdx(uint32_t handle) const;

    GpuUniformHandle sampler_uniform        = kGpuInvalidHandle;
    GpuUniformHandle skybox_sampler_uniform = kGpuInvalidHandle;
    GpuUniformHandle skybox_tint_uniform    = kGpuInvalidHandle;
    GpuTextureHandle default_cube_tex       = kGpuInvalidHandle;
    GpuTextureHandle active_env_tex         = kGpuInvalidHandle;
    bool             has_skybox             = false;

    static std::vector<uint8_t> GenerateMips(uint32_t width, uint32_t height,
                                       const uint8_t *pixels, uint8_t *out_num_mips);

private:
    std::vector<TextureEntry> textures_;
};

} // namespace kernel_engine::render::bgfx
