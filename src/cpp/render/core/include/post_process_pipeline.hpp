#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class GeometryManager;
class TextureManager;

/**
 * @brief Manages full-screen post-processing effects using the HAL.
 */
class KE_RENDER_API PostProcessPipeline
{
public:
    ke_result SetupPostProcess(RenderContext& ctx, GeometryManager& geom, GpuProgramHandle& bright, GpuProgramHandle& blur, GpuProgramHandle& tone);
    ke_result SetupSsao(RenderContext& ctx, GpuProgramHandle& prepass, GpuProgramHandle& ssao, GpuProgramHandle& ssao_blur);

    ke_result SetTonemapping(RenderContext& ctx, ke_bool enabled, float exposure, float gamma);
    ke_result SetBloom(RenderContext& ctx, ke_bool enabled, float threshold, float intensity);
    ke_result SetSsao(RenderContext& ctx, ke_bool enabled, float radius, float bias, float strength);

    void SubmitPostProcess(RenderContext& ctx, GeometryManager& geom, TextureManager& tex, GpuProgramHandle bright, GpuProgramHandle blur, GpuProgramHandle tone);
    void SubmitSsao(RenderContext& ctx, GeometryManager& geom, TextureManager& tex, GpuProgramHandle ssao, GpuProgramHandle ssao_blur);

    void Shutdown();

    GpuFrameBufferHandle GetHdrFb() const { return hdr_fb_; }
    GpuFrameBufferHandle GetGbufFb() const { return gbuf_fb_; }
    bool IsSsaoEnabled() const { return ssao_enabled_; }

private:
    GpuFrameBufferHandle hdr_fb_ = kGpuInvalidHandle;
    GpuTextureHandle     hdr_tex_ = kGpuInvalidHandle;
    GpuTextureHandle     hdr_depth_tex_ = kGpuInvalidHandle;
    GpuTextureHandle     hdr_color_tex_ = kGpuInvalidHandle;

    GpuFrameBufferHandle gbuf_fb_ = kGpuInvalidHandle;
    GpuTextureHandle     gbuf_norm_tex_ = kGpuInvalidHandle;
    GpuTextureHandle     gbuf_depth_tex_ = kGpuInvalidHandle;

    GpuFrameBufferHandle bright_fb_ = kGpuInvalidHandle;
    GpuFrameBufferHandle blur_a_fb_ = kGpuInvalidHandle;
    GpuFrameBufferHandle blur_b_fb_ = kGpuInvalidHandle;

    GpuUniformHandle hdr_tex_uniform_        = kGpuInvalidHandle;
    GpuUniformHandle bloom_tex_uniform_      = kGpuInvalidHandle;
    GpuUniformHandle blur_tex_uniform_       = kGpuInvalidHandle;
    GpuUniformHandle bloom_params_uniform_   = kGpuInvalidHandle;
    GpuUniformHandle blur_params_uniform_    = kGpuInvalidHandle;
    GpuUniformHandle tonemap_params_uniform_ = kGpuInvalidHandle;

    bool bloom_enabled_ = false;
    float bloom_threshold_ = 0.8f;
    float bloom_intensity_ = 1.0f;

    bool tonemap_enabled_ = false;
    float exposure_ = 1.0f;
    float gamma_ = 2.2f;

    bool ssao_enabled_ = false;
    float ssao_radius_ = 0.5f;
    float ssao_bias_ = 0.025f;
    float ssao_strength_ = 1.0f;

    bool pp_enabled_ = false;
    uint32_t pp_w_ = 0;
    uint32_t pp_h_ = 0;
};

} // namespace kernel_engine::render::bgfx
