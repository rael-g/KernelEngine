#pragma once

#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <cstdint>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class GeometryManager;
class TextureManager;

/**
 * @brief Manages HDR, Bloom, SSAO and Tonemapping passes using the HAL.
 */
class KE_RENDER_API PostProcessPipeline
{
public:
    ke_result SetTonemapping(RenderContext& ctx, ke_bool enabled, float exposure, float gamma);
    ke_result SetBloom(RenderContext& ctx, ke_bool enabled, float threshold, float intensity);
    ke_result SetSsao(RenderContext& ctx, ke_bool enabled, float radius, float bias, float strength);

    ke_result SetupPostProcess(RenderContext& ctx, 
                               GeometryManager& geometry,
                               GpuProgramHandle& out_bright_prog, 
                               GpuProgramHandle& out_blur_prog, 
                               GpuProgramHandle& out_tonemap_prog);

    ke_result SubmitPostProcess(RenderContext& ctx, 
                                const GeometryManager& geometry,
                                const TextureManager& textures,
                                GpuProgramHandle bright_prog, 
                                GpuProgramHandle blur_prog, 
                                GpuProgramHandle tonemap_prog);

    ke_result SetupSsao(RenderContext& ctx, 
                        GpuProgramHandle& out_prepass_prog, 
                        GpuProgramHandle& out_ssao_prog, 
                        GpuProgramHandle& out_ssao_blur_prog);

    ke_result SubmitSsao(RenderContext& ctx, 
                         const GeometryManager& geometry,
                         const TextureManager& textures,
                         GpuProgramHandle ssao_prog, 
                         GpuProgramHandle ssao_blur_prog);

    void Shutdown();

    bool IsSsaoEnabled() const { return ssao_enabled_; }
    GpuFrameBufferHandle GetGbufFb() const { return gbuf_fb_; }
    GpuFrameBufferHandle GetHdrFb() const { return hdr_fb_; }
    GpuTextureHandle GetSsaoBlurTex() const { return ssao_blur_tex_; }

    GpuUniformHandle s_gbuf_normal_u  = kGpuInvalidHandle;
    GpuUniformHandle s_gbuf_depth_u   = kGpuInvalidHandle;
    GpuUniformHandle s_ssao_blurred_u = kGpuInvalidHandle;
    GpuUniformHandle ssao_state_u     = kGpuInvalidHandle;

private:
    GpuFrameBufferHandle hdr_fb_          = kGpuInvalidHandle;
    GpuFrameBufferHandle bright_fb_       = kGpuInvalidHandle;
    GpuTextureHandle     hdr_color_tex_   = kGpuInvalidHandle;
    GpuFrameBufferHandle blur_a_fb_       = kGpuInvalidHandle;
    GpuFrameBufferHandle blur_b_fb_       = kGpuInvalidHandle;

    GpuUniformHandle hdr_tex_uniform_        = kGpuInvalidHandle;
    GpuUniformHandle bloom_tex_uniform_      = kGpuInvalidHandle;
    GpuUniformHandle blur_tex_uniform_       = kGpuInvalidHandle;
    GpuUniformHandle bloom_params_uniform_   = kGpuInvalidHandle;
    GpuUniformHandle blur_params_uniform_    = kGpuInvalidHandle;
    GpuUniformHandle tonemap_params_uniform_ = kGpuInvalidHandle;

    bool  pp_enabled_      = false;
    float exposure_        = 1.0f;
    float gamma_           = 2.2f;
    bool  bloom_enabled_   = false;
    float bloom_threshold_ = 1.0f;
    float bloom_intensity_ = 0.5f;

    int32_t pp_w_ = 0, pp_h_ = 0;

    // SSAO resources
    GpuFrameBufferHandle gbuf_fb_            = kGpuInvalidHandle;
    GpuTextureHandle     gbuf_normal_tex_    = kGpuInvalidHandle;
    GpuTextureHandle     gbuf_lin_depth_tex_ = kGpuInvalidHandle;
    GpuFrameBufferHandle ssao_raw_fb_        = kGpuInvalidHandle;
    GpuTextureHandle     ssao_raw_tex_       = kGpuInvalidHandle;
    GpuFrameBufferHandle ssao_blur_fb_       = kGpuInvalidHandle;
    GpuTextureHandle     ssao_blur_tex_      = kGpuInvalidHandle;
    GpuTextureHandle     ssao_noise_tex_     = kGpuInvalidHandle;

    GpuUniformHandle s_ssao_noise_u_     = kGpuInvalidHandle;
    GpuUniformHandle s_ssao_input_u_     = kGpuInvalidHandle;
    GpuUniformHandle ssao_params_u_      = kGpuInvalidHandle;
    GpuUniformHandle ssao_proj_info_u_   = kGpuInvalidHandle;
    GpuUniformHandle ssao_blur_params_u_ = kGpuInvalidHandle;
    GpuUniformHandle ssao_kernel_u_      = kGpuInvalidHandle;

    float ssao_kernel_data_[kSsaoKernelSize * 4]{};
    float ssao_proj_info_[4]{};

    bool  ssao_enabled_  = false;
    float ssao_radius_   = 0.5f;
    float ssao_bias_     = 0.025f;
    float ssao_strength_ = 1.0f;
};

} // namespace kernel_engine::render::bgfx
