#include "post_process_pipeline.hpp"
#include <render_logging.hpp>
#include "render_context.hpp"
#include "geometry_manager.hpp"
#include "texture_manager.hpp"
#include "shader_provider.hpp"
#include "gpu_device.hpp"
#include <vector>
#include <cmath>
#include <algorithm>


namespace kernel_engine::render::core
{

ke_result PostProcessPipeline::SetTonemapping(RenderContext& ctx, ke_bool enabled, float exposure, float gamma)
{
    if (enabled && hdr_fb_ == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_NOT_INITIALIZED, "SetTonemapping", "HDR framebuffer not initialized");
    pp_enabled_ = (enabled != 0);
    exposure_   = exposure;
    gamma_      = gamma;
    return KE_OK;
}

ke_result PostProcessPipeline::SetBloom(RenderContext& ctx, ke_bool enabled, float threshold, float intensity)
{
    if (enabled && bright_fb_ == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_NOT_INITIALIZED, "SetBloom", "Bright framebuffer not initialized");
    bloom_enabled_   = (enabled != 0);
    bloom_threshold_ = threshold;
    bloom_intensity_ = intensity;
    return KE_OK;
}

ke_result PostProcessPipeline::SetSsao(RenderContext& ctx, ke_bool enabled, float radius, float bias, float strength)
{
    ssao_enabled_  = (enabled != 0);
    ssao_radius_   = radius;
    ssao_bias_     = bias;
    ssao_strength_ = strength;
    return KE_OK;
}

ke_result PostProcessPipeline::SetupPostProcess(RenderContext& ctx, 
                                                GeometryManager& geometry,
                                                GpuProgramHandle& out_bright_prog, 
                                                GpuProgramHandle& out_blur_prog, 
                                                GpuProgramHandle& out_tonemap_prog)
{
    if (!ctx.gpu || !ctx.shader_provider)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "SetupPostProcess", "GPU or ShaderProvider not set");

    auto load_shader = [&](const char* name) -> GpuShaderHandle {
        const GpuMemoryBuffer* mem = ctx.shader_provider->LoadShaderBinary(ctx, name);
        if (!mem) return kGpuInvalidHandle;
        return ctx.gpu->CreateShader(mem);
    };

    // vs_fullscreen derives UV from position (NDC->UV with bgfx Y-flip).
    // Its vertex input is position-only, matching the project's geometry_.fullscreen_vb.
    GpuShaderHandle vs_screen = load_shader("vs_fullscreen");
    GpuShaderHandle fs_bright = load_shader("fs_bright_pass");
    GpuShaderHandle fs_blur   = load_shader("fs_blur");
    GpuShaderHandle fs_tone   = load_shader("fs_tonemap");

    if (vs_screen == kGpuInvalidHandle || fs_bright == kGpuInvalidHandle ||
        fs_blur == kGpuInvalidHandle || fs_tone == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "SetupPostProcess", "Shader loading failed");

    // vs_screen is shared; don't destroy it until the last program is created.
    out_bright_prog  = ctx.gpu->CreateProgram(vs_screen, fs_bright, false);
    out_blur_prog    = ctx.gpu->CreateProgram(vs_screen, fs_blur,   false);
    out_tonemap_prog = ctx.gpu->CreateProgram(vs_screen, fs_tone,   true);
    ctx.gpu->DestroyShader(vs_screen);

    uint16_t w = (uint16_t)ctx.view_w;
    uint16_t h = (uint16_t)ctx.view_h;

    pp_w_ = (uint32_t)(w / 2);
    pp_h_ = (uint32_t)(h / 2);

    auto make_color_fb = [&](uint32_t fw, uint32_t fh, uint32_t fmt) -> GpuFrameBufferHandle {
        GpuTextureHandle tex = ctx.gpu->CreateTexture2D((uint16_t)fw, (uint16_t)fh, false, 1, fmt, kTexFlagRT, nullptr);
        return ctx.gpu->CreateFrameBuffer(1, &tex, true);
    };

    hdr_fb_    = make_color_fb(w, h, kTexFmtRGBA8);
    bright_fb_ = make_color_fb(pp_w_, pp_h_, kTexFmtRGBA8);
    blur_a_fb_ = make_color_fb(pp_w_, pp_h_, kTexFmtRGBA8);
    blur_b_fb_ = make_color_fb(pp_w_, pp_h_, kTexFmtRGBA8);

    hdr_tex_uniform_        = ctx.gpu->CreateUniform("s_hdrTex",       GpuUniformType::Sampler, 1);
    bloom_tex_uniform_      = ctx.gpu->CreateUniform("s_bloomTex",     GpuUniformType::Sampler, 1);
    blur_tex_uniform_       = ctx.gpu->CreateUniform("s_blurTex",      GpuUniformType::Sampler, 1);
    bloom_params_uniform_   = ctx.gpu->CreateUniform("u_bloomParams",  GpuUniformType::Vec4, 1);
    blur_params_uniform_    = ctx.gpu->CreateUniform("u_blurParams",   GpuUniformType::Vec4, 1);
    tonemap_params_uniform_ = ctx.gpu->CreateUniform("u_tonemapParams",GpuUniformType::Vec4, 1);

    return KE_OK;
}

ke_result PostProcessPipeline::SetupSsao(RenderContext& ctx, GpuProgramHandle& out_prepass, GpuProgramHandle& out_ssao, GpuProgramHandle& out_ssao_blur)
{
    // Implementation placeholder
    return KE_OK;
}

void PostProcessPipeline::SubmitPostProcess(RenderContext& ctx, GeometryManager& geom, TextureManager& tex,
                                            GpuProgramHandle bright_prog, GpuProgramHandle blur_prog, GpuProgramHandle tonemap_prog)
{
    if (!ctx.gpu || !pp_enabled_ || hdr_fb_ == kGpuInvalidHandle) return;

    // BGFX view layout (per project memory):
    // 1=SCENE (HDR), 3=BRIGHT, 4=BLUR_H, 5=BLUR_V, 6=TONEMAP composite → backbuffer
    constexpr uint8_t kBrightView   = 3;
    constexpr uint8_t kBlurHView    = 4;
    constexpr uint8_t kBlurVView    = 5;
    constexpr uint8_t kTonemapView  = 6;

    GpuTextureHandle hdr_color_tex = ctx.gpu->GetTexture(hdr_fb_, 0);

    auto submit_fs = [&](uint8_t view, GpuFrameBufferHandle fb, int w, int h, GpuProgramHandle prog) {
        if (fb != kGpuInvalidHandle) {
            ctx.gpu->SetViewFrameBuffer(view, fb);
            ctx.gpu->SetViewClear(view, 0x0001, 0x000000ff, 1.0f, 0); // CLEAR_COLOR
        } else {
            ctx.gpu->SetViewFrameBuffer(view, kGpuInvalidHandle);
            ctx.gpu->SetViewClear(view, 0, 0, 0, 0); // CLEAR_NONE
        }
        ctx.gpu->SetViewRect(view, 0, 0, (uint16_t)w, (uint16_t)h);
        ctx.gpu->SetVertexBuffer(0, geom.fullscreen_vb);
        ctx.gpu->SetIndexBufferStatic(geom.fullscreen_ib);
        // BGFX_STATE_WRITE_R|G|B|A = 0x0F. Previous mask was 0x01|0x08 (only R+A), which
        // left G and B unwritten → all output looked red.
        ctx.gpu->SetState(0x000000000000000FULL, 0);
        ctx.gpu->Submit(view, prog, 0, false);
    };

    // Bloom chain (optional): bright-pass → blur H → blur V
    GpuTextureHandle bloom_result_tex = tex.default_2d_tex;
    if (bloom_enabled_ && bright_fb_ != kGpuInvalidHandle && bright_prog != kGpuInvalidHandle) {
        float bp[4] = { bloom_threshold_, 0.f, 0.f, 0.f };
        ctx.gpu->SetUniform(bloom_params_uniform_, bp, 1);
        ctx.gpu->SetTexture(0, hdr_tex_uniform_, hdr_color_tex, 0xFFFFFFFF);
        submit_fs(kBrightView, bright_fb_, pp_w_, pp_h_, bright_prog);

        float bh[4] = { 1.f / (float)pp_w_, 0.f, 0.f, 0.f };
        ctx.gpu->SetUniform(blur_params_uniform_, bh, 1);
        ctx.gpu->SetTexture(0, blur_tex_uniform_, ctx.gpu->GetTexture(bright_fb_, 0), 0xFFFFFFFF);
        submit_fs(kBlurHView, blur_a_fb_, pp_w_, pp_h_, blur_prog);

        float bv[4] = { 0.f, 1.f / (float)pp_h_, 0.f, 0.f };
        ctx.gpu->SetUniform(blur_params_uniform_, bv, 1);
        ctx.gpu->SetTexture(0, blur_tex_uniform_, ctx.gpu->GetTexture(blur_a_fb_, 0), 0xFFFFFFFF);
        submit_fs(kBlurVView, blur_b_fb_, pp_w_, pp_h_, blur_prog);

        bloom_result_tex = ctx.gpu->GetTexture(blur_b_fb_, 0);
    }

    // Tonemap composite → backbuffer (kGpuInvalidHandle = default FB)
    float tp[4] = { exposure_, bloom_enabled_ ? bloom_intensity_ : 0.f, 1.f / gamma_, 0.f };
    ctx.gpu->SetUniform(tonemap_params_uniform_, tp, 1);
    ctx.gpu->SetTexture(0, hdr_tex_uniform_, hdr_color_tex, 0xFFFFFFFF);
    ctx.gpu->SetTexture(1, bloom_tex_uniform_, bloom_result_tex, 0xFFFFFFFF);
    submit_fs(kTonemapView, kGpuInvalidHandle, ctx.view_w, ctx.view_h, tonemap_prog);
}

void PostProcessPipeline::SubmitSsao(RenderContext& ctx, GeometryManager& geom, TextureManager& tex, GpuProgramHandle ssao, GpuProgramHandle ssao_blur)
{
    // SSAO not yet re-implemented after FrameSubmitter extraction. Tracked separately.
}

void PostProcessPipeline::Shutdown()
{
}

} // namespace kernel_engine::render::core
