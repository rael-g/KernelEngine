#include "texture_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <vector>
#include <cstring>
#include <cmath>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

std::vector<uint8_t> TextureManager::GenerateMips(uint32_t width, uint32_t height,
                                                     const uint8_t *pixels, uint8_t *out_num_mips)
{
    uint32_t maxDim = std::max(width, height);
    uint8_t  numMips = 0;
    for (uint32_t d = maxDim; d > 0; d >>= 1) ++numMips;

    uint32_t total = 0;
    { uint32_t w = width, h = height;
      for (uint8_t i = 0; i < numMips; ++i) {
          total += w * h * 4;
          w = w > 1 ? w >> 1 : 1;
          h = h > 1 ? h >> 1 : 1;
      }
    }

    std::vector<uint8_t> buf(total);
    std::memcpy(buf.data(), pixels, width * height * 4);

    const uint8_t *src = buf.data();
    uint32_t srcW = width, srcH = height;
    uint8_t *dst = buf.data() + width * height * 4;

    for (uint8_t mip = 1; mip < numMips; ++mip) {
        uint32_t dstW = srcW > 1 ? srcW >> 1 : 1;
        uint32_t dstH = srcH > 1 ? srcH >> 1 : 1;
        for (uint32_t y = 0; y < dstH; ++y) {
            for (uint32_t x = 0; x < dstW; ++x) {
                uint32_t x0 = x * 2, y0 = y * 2;
                uint32_t x1 = srcW > 1 ? x0 + 1 : x0;
                uint32_t y1 = srcH > 1 ? y0 + 1 : y0;
                const uint8_t *p00 = src + (y0 * srcW + x0) * 4;
                const uint8_t *p10 = src + (y0 * srcW + x1) * 4;
                const uint8_t *p01 = src + (y1 * srcW + x0) * 4;
                const uint8_t *p11 = src + (y1 * srcW + x1) * 4;
                for (int c = 0; c < 4; ++c)
                    dst[(y * dstW + x) * 4 + c] =
                        (uint8_t)((p00[c] + p10[c] + p01[c] + p11[c] + 2) >> 2);
            }
        }
        src = dst; dst += dstW * dstH * 4;
        srcW = dstW; srcH = dstH;
    }

    *out_num_mips = numMips;
    return buf;
}

ke_result TextureManager::CreateTextureRgba(RenderContext& ctx, uint32_t width, uint32_t height,
                                               const uint8_t *pixels,
                                               ke_texture_handle *out_handle)
{
    if (!pixels || !out_handle || width == 0 || height == 0 || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;

    uint8_t numMips;
    std::vector<uint8_t> mipData = GenerateMips(width, height, pixels, &numMips);
    GpuTextureHandle idx = ctx.gpu->CreateTexture2D(
        (uint16_t)width, (uint16_t)height, numMips > 1, 1,
        6, 0, // 6 is RGBA8 in bgfx
        ctx.gpu->Copy(mipData.data(), (uint32_t)mipData.size()));

    if (idx == kGpuInvalidHandle) return KE_ERROR_RENDER;
    textures_.push_back({idx, true});
    *out_handle = (ke_texture_handle)(textures_.size() - 1);
    return KE_OK;
}

ke_result TextureManager::DestroyTexture(RenderContext& ctx, ke_texture_handle handle)
{
    if (handle >= (ke_texture_handle)textures_.size() || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    auto &t = textures_[handle];
    if (t.idx != kGpuInvalidHandle) ctx.gpu->DestroyTexture(t.idx);
    t.idx   = kGpuInvalidHandle;
    t.valid = false;
    return KE_OK;
}

ke_result TextureManager::CreateCubemapRgba(RenderContext& ctx, uint32_t size, const uint8_t *data,
                                               ke_texture_handle *out_handle)
{
    if (!data || !out_handle || size == 0 || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;

    uint32_t faceBytes = size * size * 4u;
    uint8_t numMips;
    std::vector<std::vector<uint8_t>> faceMips(6);
    for (int f = 0; f < 6; ++f)
        faceMips[f] = GenerateMips(size, size, data + f * faceBytes, &numMips);

    std::vector<uint32_t> mipFaceSize(numMips);
    { uint32_t s = size;
      for (uint8_t m = 0; m < numMips; ++m) {
          mipFaceSize[m] = s * s * 4u;
          s = s > 1 ? s >> 1 : 1;
      }
    }

    uint32_t total = 0;
    for (uint8_t m = 0; m < numMips; ++m) total += 6u * mipFaceSize[m];

    std::vector<uint8_t> cubeBuf(total);
    uint8_t *p = cubeBuf.data();
    for (int f = 0; f < 6; ++f) {
        uint32_t faceOffset = 0;
        for (uint8_t m = 0; m < numMips; ++m) {
            std::memcpy(p, faceMips[f].data() + faceOffset, mipFaceSize[m]);
            p += mipFaceSize[m];
            faceOffset += mipFaceSize[m];
        }
    }

    GpuTextureHandle idx = ctx.gpu->CreateTextureCube(
        (uint16_t)size, numMips > 1, 1,
        6, 0, // RGBA8
        ctx.gpu->Copy(cubeBuf.data(), (uint32_t)cubeBuf.size()));

    if (idx == kGpuInvalidHandle) return KE_ERROR_RENDER;
    textures_.push_back({idx, true});
    *out_handle = (ke_texture_handle)(textures_.size() - 1);
    return KE_OK;
}

ke_result TextureManager::SubmitSkybox(RenderContext& ctx, 
                                       ke_texture_handle cubemap_handle,
                                       GpuProgramHandle skybox_program,
                                       GpuVertexBufferHandle skybox_vb,
                                       GpuIndexBufferHandle skybox_ib,
                                       GpuUniformHandle skybox_sampler,
                                       GpuUniformHandle skybox_tint)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;
    if (skybox_program == kGpuInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    if (skybox_vb == kGpuInvalidHandle)      return KE_ERROR_NOT_INITIALIZED;
    if (cubemap_handle >= (ke_texture_handle)textures_.size()) return KE_ERROR_INVALID_ARGUMENT;
    const auto &tex = textures_[cubemap_handle];
    if (!tex.valid) return KE_ERROR_INVALID_ARGUMENT;

    float model[16] = {
        1.f, 0.f, 0.f, 0.f,
        0.f, 1.f, 0.f, 0.f,
        0.f, 0.f, 1.f, 0.f,
        ctx.camera_pos[0], ctx.camera_pos[1], ctx.camera_pos[2], 1.f
    };
    ctx.gpu->SetTransform(model, 1);

    float tint[4] = {1.f, 1.f, 1.f, 1.f};
    ctx.gpu->SetUniform(skybox_tint, tint, 1);
    ctx.gpu->SetTexture(0, skybox_sampler, tex.idx, 0xFFFFFFFF);
    ctx.gpu->SetVertexBuffer(0, skybox_vb);
    ctx.gpu->SetIndexBufferStatic(skybox_ib);
    
    // Default skybox state (Cull CW, LessEqual)
    ctx.gpu->SetState(0x0000001000000000ULL | 0x0000000000000010ULL | 0x0000000000000001ULL | 0x0000000000000002ULL | 0x0000000000000100ULL, 0);
    ctx.gpu->Submit(kSceneView, skybox_program, 0, false);

    has_skybox     = true;
    active_env_tex = tex.idx;
    return KE_OK;
}

void TextureManager::Shutdown()
{
    textures_.clear();
}

GpuTextureHandle TextureManager::GetTextureIdx(uint32_t handle) const
{
    if (handle < textures_.size() && textures_[handle].valid) return textures_[handle].idx;
    return kGpuInvalidHandle;
}

} // namespace kernel_engine::render::bgfx
