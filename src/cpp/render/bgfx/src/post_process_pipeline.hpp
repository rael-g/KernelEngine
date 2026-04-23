#pragma once

#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "internal_types.hpp"
#include <cstdint>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class GeometryManager;
class TextureManager;

/**
 * @brief Manages HDR, Bloom, SSAO and Tonemapping passes.
 */
class KE_RENDER_API PostProcessPipeline
{
public:
    ke_result SetTonemapping(RenderContext& ctx, ke_bool enabled, float exposure, float gamma);
    ke_result SetBloom(RenderContext& ctx, ke_bool enabled, float threshold, float intensity);
    ke_result SetSsao(RenderContext& ctx, ke_bool enabled, float radius, float bias, float strength);

    ke_result SetupPostProcess(RenderContext& ctx, 
                               GeometryManager& geometry,
                               uint16_t& out_bright_prog, 
                               uint16_t& out_blur_prog, 
                               uint16_t& out_tonemap_prog);

    ke_result SubmitPostProcess(RenderContext& ctx, 
                                const GeometryManager& geometry,
                                const TextureManager& textures,
                                uint16_t bright_prog, 
                                uint16_t blur_prog, 
                                uint16_t tonemap_prog);

    ke_result SetupSsao(RenderContext& ctx, 
                        uint16_t& out_prepass_prog, 
                        uint16_t& out_ssao_prog, 
                        uint16_t& out_ssao_blur_prog);

    ke_result SubmitSsao(RenderContext& ctx, 
                         const GeometryManager& geometry,
                         const TextureManager& textures,
                         uint16_t ssao_prog, 
                         uint16_t ssao_blur_prog);

    void Shutdown();

    bool IsSsaoEnabled() const { return ssao_enabled_; }
    uint16_t GetGbufFb() const { return gbuf_fb_; }
    uint16_t GetHdrFb() const { return hdr_fb_; }
    uint16_t GetSsaoBlurTex() const { return ssao_blur_tex_; }

    uint16_t s_gbuf_normal_u  = kInvalidHandle;
    uint16_t s_gbuf_depth_u   = kInvalidHandle;
    uint16_t s_ssao_blurred_u = kInvalidHandle;
    uint16_t ssao_state_u     = kInvalidHandle;

private:
    uint16_t hdr_fb_          = kInvalidHandle;
    uint16_t bright_fb_       = kInvalidHandle;
    uint16_t hdr_color_tex_   = kInvalidHandle;
    uint16_t blur_a_fb_       = kInvalidHandle;
    uint16_t blur_b_fb_       = kInvalidHandle;

    uint16_t hdr_tex_uniform_        = kInvalidHandle;
    uint16_t bloom_tex_uniform_      = kInvalidHandle;
    uint16_t blur_tex_uniform_       = kInvalidHandle;
    uint16_t bloom_params_uniform_   = kInvalidHandle;
    uint16_t blur_params_uniform_    = kInvalidHandle;
    uint16_t tonemap_params_uniform_ = kInvalidHandle;

    bool  pp_enabled_      = false;
    float exposure_        = 1.0f;
    float gamma_           = 2.2f;
    bool  bloom_enabled_   = false;
    float bloom_threshold_ = 1.0f;
    float bloom_intensity_ = 0.5f;

    int32_t pp_w_ = 0, pp_h_ = 0;

    // SSAO resources
    uint16_t gbuf_fb_            = kInvalidHandle;
    uint16_t gbuf_normal_tex_    = kInvalidHandle;
    uint16_t gbuf_lin_depth_tex_ = kInvalidHandle;
    uint16_t ssao_raw_fb_        = kInvalidHandle;
    uint16_t ssao_raw_tex_       = kInvalidHandle;
    uint16_t ssao_blur_fb_       = kInvalidHandle;
    uint16_t ssao_blur_tex_      = kInvalidHandle;
    uint16_t ssao_noise_tex_     = kInvalidHandle;

    uint16_t s_ssao_noise_u_     = kInvalidHandle;
    uint16_t s_ssao_input_u_     = kInvalidHandle;
    uint16_t ssao_params_u_      = kInvalidHandle;
    uint16_t ssao_proj_info_u_   = kInvalidHandle;
    uint16_t ssao_blur_params_u_ = kInvalidHandle;
    uint16_t ssao_kernel_u_      = kInvalidHandle;

    float ssao_kernel_data_[kSsaoKernelSize * 4]{};    float ssao_proj_info_[4]{};

    bool  ssao_enabled_  = false;
    float ssao_radius_   = 0.5f;
    float ssao_bias_     = 0.025f;
    float ssao_strength_ = 1.0f;
};

} // namespace kernel_engine::render::bgfx
