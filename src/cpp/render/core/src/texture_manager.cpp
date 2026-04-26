#include "../include/texture_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <vector>
#include <cstring>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result TextureManager::CreateTextureRgba(RenderContext& ctx, uint32_t w, uint32_t h, const uint8_t *px, ke_texture_handle *out)
{
    if (!px || !out || w == 0 || h == 0 || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    
    GpuTextureHandle htex = ctx.gpu->CreateTexture2D((uint16_t)w, (uint16_t)h, false, 1, kTexFmtRGBA8, 0, ctx.gpu->Copy(px, w * h * 4));
    if (htex == kGpuInvalidHandle) return KE_ERROR_RENDER;

    textures_.push_back(htex);
    *out = (ke_texture_handle)(textures_.size() - 1);
    return KE_OK;
}

ke_result TextureManager::CreateCubemapRgba(RenderContext& ctx, uint32_t s, const uint8_t *d, ke_texture_handle *out)
{
    if (!d || !out || s == 0 || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    GpuTextureHandle h = ctx.gpu->CreateTextureCube((uint16_t)s, false, 1, kTexFmtRGBA8, 0, ctx.gpu->Copy(d, s * s * 4 * 6));
    if (h == kGpuInvalidHandle) return KE_ERROR_RENDER;
    textures_.push_back(h);
    *out = (ke_texture_handle)(textures_.size() - 1);
    return KE_OK;
}

ke_result TextureManager::DestroyTexture(RenderContext& ctx, ke_texture_handle h)
{
    if (h >= (ke_texture_handle)textures_.size() || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    if (textures_[h] != kGpuInvalidHandle) ctx.gpu->DestroyTexture(textures_[h]);
    textures_[h] = kGpuInvalidHandle;
    return KE_OK;
}

ke_result TextureManager::SubmitSkybox(RenderContext& ctx, ke_texture_handle h, GpuProgramHandle prog, GpuVertexBufferHandle vb, GpuIndexBufferHandle ib, GpuUniformHandle sampler, GpuUniformHandle tint)
{
    if (!ctx.gpu || prog == kGpuInvalidHandle) return KE_ERROR_RENDER;
    GpuTextureHandle tex = GetTextureIdx(h);
    if (tex == kGpuInvalidHandle) tex = default_cube_tex;
    
    ctx.gpu->SetTexture(0, sampler, tex, 0xFFFFFFFF);
    float white[4] = {1,1,1,1};
    ctx.gpu->SetUniform(tint, white, 1);
    ctx.gpu->SetVertexBuffer(0, vb);
    ctx.gpu->SetIndexBufferStatic(ib);
    // BGFX_STATE_WRITE_RGB | BGFX_STATE_DEPTH_TEST_LEQUAL (0x20, not 0x10=LESS)
    ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000002ULL | 0x0000000000000004ULL | 0x0000000000000020ULL, 0);
    ctx.gpu->Submit(1 /*SCENE*/, prog, 0, false);
    return KE_OK;
}

GpuTextureHandle TextureManager::GetTextureIdx(ke_texture_handle h) const
{
    if (h < (ke_texture_handle)textures_.size()) return textures_[h];
    return kGpuInvalidHandle;
}

void TextureManager::Shutdown()
{
    textures_.clear();
}

} // namespace kernel_engine::render::bgfx
