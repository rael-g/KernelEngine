#pragma once

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/asset/asset_loader.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "internal_types.hpp"
#include <vector>
#include <cstdint>

namespace kernel_engine::render::bgfx
{

struct RenderContext;

struct TextureEntry
{
    uint16_t idx  = kInvalidHandle;
    bool valid    = false;
};

/**
 * @brief Manages texture resources and cubemaps.
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
                           uint16_t skybox_program,
                           uint16_t skybox_vb,
                           uint16_t skybox_ib,
                           uint16_t skybox_sampler,
                           uint16_t skybox_tint);

    void Shutdown();

    uint16_t GetTextureIdx(uint32_t handle) const;

    uint16_t sampler_uniform  = kInvalidHandle;
    uint16_t default_cube_tex = kInvalidHandle;
    uint16_t active_env_tex   = kInvalidHandle;
    bool     has_skybox       = false;
    
    uint16_t skybox_sampler_uniform = kInvalidHandle;
    uint16_t skybox_tint_uniform    = kInvalidHandle;

protected:
    std::vector<uint8_t> GenerateMips(uint32_t width, uint32_t height,
                                       const uint8_t *pixels, uint8_t *out_num_mips);

private:
    std::vector<TextureEntry> textures_;
};

} // namespace kernel_engine::render::bgfx
