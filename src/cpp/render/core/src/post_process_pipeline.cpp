#include "../include/post_process_pipeline.hpp"
#include "render_context.hpp"
#include "../include/geometry_manager.hpp"
#include "../include/texture_manager.hpp"
#include "../include/shader_provider.hpp"
#include "gpu_device.hpp"
#include <vector>
#include <cmath>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result PostProcessPipeline::SetTonemapping(RenderContext& ctx, ke_bool enabled, float exposure, float gamma)
{
    if (enabled && hdr_fb_ == kGpuInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    pp_enabled_ = (enabled != 0);
    exposure_   = exposure;
    gamma_      = gamma;
    return KE_OK;
}

ke_result PostProcessPipeline::SetBloom(RenderContext& ctx, ke_bool enabled, float threshold, float intensity)
{
    if (enabled && bright_fb_ == kGpuInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
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
    if (!ctx.gpu || !ctx.shader_provider) return KE_ERROR_RENDER;

    auto load_shader = [&](const char* name) -> GpuShaderHandle {
        const GpuMemoryBuffer* mem = ctx.shader_provider->LoadShaderBinary(ctx, name);
        if (!mem) return kGpuInvalidHandle;
        return ctx.gpu->CreateShader(mem);
    };

    GpuShaderHandle vs_screen = load_shader("vs_screen");
    GpuShaderHandle fs_bright = load_shader("fs_bright_pass");
    GpuShaderHandle fs_blur   = load_shader("fs_blur");
    GpuShaderHandle fs_tone   = load_shader("fs_tonemap");

    if (vs_screen == kGpuInvalidHandle || fs_bright == kGpuInvalidHandle ||
        fs_blur == kGpuInvalidHandle || fs_tone == kGpuInvalidHandle)
        return KE_ERROR_RENDER;

    // vs_screen is shared; don't destroy it until the last program is created.
    out_bright_prog  = ctx.gpu->CreateProgram(vs_screen, fs_bright, false);
    out_blur_prog    = ctx.gpu->CreateProgram(vs_screen, fs_blur,   false);
    out_tonemap_prog = ctx.gpu->CreateProgram(vs_screen, fs_tone,   true);
    ctx.gpu->DestroyShader(vs_screen);

    uint16_t w = (uint16_t)ctx.view_w;
    uint16_t h = (uint16_t)ctx.view_h;

    pp_w_ = (uint32_t)(w / 2);
    pp_h_ = (uint32_t)(h / 2);

    auto make_color_fb = [&](uint32_t fw, uint32_t fh) -> GpuFrameBufferHandle {
        GpuTextureHandle tex = ctx.gpu->CreateTexture2D((uint16_t)fw, (uint16_t)fh, false, 1, kTexFmtRGBA8, kTexFlagRT, nullptr);
        return ctx.gpu->CreateFrameBuffer(1, &tex, true);
    };

    bright_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_a_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_b_fb_ = make_color_fb(pp_w_, pp_h_);

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

void PostProcessPipeline::SubmitPostProcess(RenderContext& ctx, GeometryManager& geom, TextureManager& tex, GpuProgramHandle bright, GpuProgramHandle blur, GpuProgramHandle tone)
{
    // Implementation placeholder
}

void PostProcessPipeline::SubmitSsao(RenderContext& ctx, GeometryManager& geom, TextureManager& tex, GpuProgramHandle ssao, GpuProgramHandle ssao_blur)
{
    // Implementation placeholder
}

void PostProcessPipeline::Shutdown()
{
}

} // namespace kernel_engine::render::bgfx
