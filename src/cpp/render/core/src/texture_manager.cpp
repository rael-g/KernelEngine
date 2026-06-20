#include "texture_manager.hpp"
#include <render_logging.hpp>
#include "render_context.hpp"
#include "gpu_device.hpp"
#include "view_ids.hpp"
#include <vector>
#include <cstring>
#include <algorithm>


namespace kernel_engine::render::core
{

bool TextureManager::CreateTextureRgba(RenderContext& ctx, uint32_t w, uint32_t h, const uint8_t *px, ke_texture_handle *out)
{
    if (!px || !out || w == 0 || h == 0 || !ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, false, "CreateTextureRgba", "Invalid arguments or GPU not set");

    GpuTextureHandle htex = ctx.gpu->CreateTexture2D((uint16_t)w, (uint16_t)h, false, 1, kTexFmtRGBA8, 0, ctx.gpu->Copy(px, w * h * 4));
    if (htex == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, false, "CreateTextureRgba", "GPU resource creation failed");

    textures_.push_back(htex);
    *out = {(uint32_t)(textures_.size() - 1)};
    return true;
}

bool TextureManager::CreateCubemapRgba(RenderContext& ctx, uint32_t s, const uint8_t *d, ke_texture_handle *out)
{
    if (!d || !out || s == 0 || !ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, false, "CreateCubemapRgba", "Invalid arguments or GPU not set");
    GpuTextureHandle h = ctx.gpu->CreateTextureCube((uint16_t)s, false, 1, kTexFmtRGBA8, 0, ctx.gpu->Copy(d, s * s * 4 * 6));
    if (h == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, false, "CreateCubemapRgba", "GPU resource creation failed");
    textures_.push_back(h);
    *out = {(uint32_t)(textures_.size() - 1)};
    return true;
}

bool TextureManager::DestroyTexture(RenderContext& ctx, ke_texture_handle h)
{
    if (h.idx >= (uint32_t)textures_.size() || !ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, false, "DestroyTexture", "Invalid texture handle or GPU not set");
    if (textures_[h.idx] != kGpuInvalidHandle) ctx.gpu->DestroyTexture(textures_[h.idx]);
    textures_[h.idx] = kGpuInvalidHandle;
    return true;
}

bool TextureManager::SubmitSkybox(RenderContext& ctx, ke_texture_handle h, GpuProgramHandle prog, GpuVertexBufferHandle vb, GpuIndexBufferHandle ib, GpuUniformHandle sampler, GpuUniformHandle tint)
{
    if (!ctx.gpu || prog == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, false, "SubmitSkybox", "GPU not set or invalid program");
    GpuTextureHandle tex = GetTextureIdx(h);
    if (tex == kGpuInvalidHandle) tex = default_cube_tex;

    ctx.gpu->SetTexture(0, sampler, tex, 0xFFFFFFFF);
    float white[4] = {1,1,1,1};
    ctx.gpu->SetUniform(tint, white, 1);
    ctx.gpu->SetVertexBuffer(0, vb);
    ctx.gpu->SetIndexBufferStatic(ib);
    ctx.gpu->SetState(GpuStateFlags::WriteRgb | GpuStateFlags::DepthTestLEqual, 0);
    ctx.gpu->Submit(Id(ViewId::Scene), prog, 0, false);
    return true;
}

GpuTextureHandle TextureManager::GetTextureIdx(ke_texture_handle h) const
{
    if (h.idx < (uint32_t)textures_.size()) return textures_[h.idx];
    return kGpuInvalidHandle;
}

void TextureManager::Shutdown()
{
    textures_.clear();
}

} // namespace kernel_engine::render::core
