#include "post_process_pipeline.hpp"
#include "render_context.hpp"
#include "geometry_manager.hpp"
#include "texture_manager.hpp"
#include "shader_provider.hpp"
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

    auto load_pp_program = [&](const char *vs_name, const char *fs_name) -> GpuProgramHandle {
        GpuShaderHandle vs = load_shader(vs_name);
        GpuShaderHandle fs = load_shader(fs_name);
        if (vs == kGpuInvalidHandle || fs == kGpuInvalidHandle)
        {
            if (vs != kGpuInvalidHandle) ctx.gpu->DestroyShader(vs);
            if (fs != kGpuInvalidHandle) ctx.gpu->DestroyShader(fs);
            return kGpuInvalidHandle;
        }
        GpuProgramHandle prog = ctx.gpu->CreateProgram(vs, fs, true);
        return prog;
    };

    out_bright_prog = load_pp_program("vs_fullscreen", "fs_bright_pass");
    out_blur_prog   = load_pp_program("vs_fullscreen", "fs_blur");
    out_tonemap_prog = load_pp_program("vs_fullscreen", "fs_tonemap");

    if (out_bright_prog == kGpuInvalidHandle || out_blur_prog == kGpuInvalidHandle || out_tonemap_prog == kGpuInvalidHandle)
        return KE_OK;

    // FS vertex layout bridge (Simplified)
    static const float kFSVerts[9] = {-1.f,-1.f,0.f,  3.f,-1.f,0.f,  -1.f,3.f,0.f};
    static const uint16_t kFSIdx[3] = {0, 1, 2};
    geometry.fullscreen_vb = ctx.gpu->CreateVertexBuffer(ctx.gpu->Copy(kFSVerts, sizeof(kFSVerts)), 0 /* Default Layout */);
    geometry.fullscreen_ib = ctx.gpu->CreateIndexBuffer(ctx.gpu->Copy(kFSIdx, sizeof(kFSIdx)));

    GpuTextureHandle hdr_color = ctx.gpu->CreateTexture2D(
        (uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1,
        21, 0x0000100000000000ULL, nullptr); // 21: RGBA16F, RT
    GpuTextureHandle hdr_depth = ctx.gpu->CreateTexture2D(
        (uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1,
        29, 0x0000200000000000ULL, nullptr); // 29: D24, RT_WRITE

    if (hdr_color == kGpuInvalidHandle || hdr_depth == kGpuInvalidHandle) return KE_OK;

    GpuTextureHandle hdr_attachments[2] = {hdr_color, hdr_depth};
    GpuFrameBufferHandle hdr_fb = ctx.gpu->CreateFrameBuffer(2, hdr_attachments, false);
    if (hdr_fb == kGpuInvalidHandle) return KE_OK;

    hdr_fb_        = hdr_fb;
    hdr_color_tex_ = hdr_color;
    ctx.gpu->DestroyTexture(hdr_depth);

    pp_w_ = (ctx.view_w + 1) / 2;
    pp_h_ = (ctx.view_h + 1) / 2;

    auto make_color_fb = [&](int w, int h) -> GpuFrameBufferHandle {
        GpuTextureHandle tex = ctx.gpu->CreateTexture2D(
            (uint16_t)w, (uint16_t)h, false, 1,
            21, 0x0000100000000000ULL, nullptr);
        if (tex == kGpuInvalidHandle) return kGpuInvalidHandle;
        return ctx.gpu->CreateFrameBuffer(1, &tex, true);
    };

    bright_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_a_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_b_fb_ = make_color_fb(pp_w_, pp_h_);

    hdr_tex_uniform_       = ctx.gpu->CreateUniform("s_hdrTex",       GpuUniformType::Sampler, 1);
    bloom_tex_uniform_     = ctx.gpu->CreateUniform("s_bloomTex",     GpuUniformType::Sampler, 1);
    blur_tex_uniform_      = ctx.gpu->CreateUniform("s_blurTex",      GpuUniformType::Sampler, 1);
    bloom_params_uniform_  = ctx.gpu->CreateUniform("u_bloomParams",  GpuUniformType::Vec4, 1);
    blur_params_uniform_   = ctx.gpu->CreateUniform("u_blurParams",   GpuUniformType::Vec4, 1);
    tonemap_params_uniform_= ctx.gpu->CreateUniform("u_tonemapParams",GpuUniformType::Vec4, 1);

    return KE_OK;
}

ke_result PostProcessPipeline::SubmitPostProcess(RenderContext& ctx, 
                                                const GeometryManager& geometry,
                                                const TextureManager& textures,
                                                GpuProgramHandle bright_prog, 
                                                GpuProgramHandle blur_prog, 
                                                GpuProgramHandle tonemap_prog)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;

    auto submit_fs = [&](uint8_t view, GpuFrameBufferHandle fb, int w, int h, GpuProgramHandle prog) {
        if (fb != kGpuInvalidHandle)
        {
            ctx.gpu->SetViewFrameBuffer(view, fb);
            // BGFX_CLEAR_COLOR
            ctx.gpu->SetViewClear(view, 0x0001, 0x000000ff, 1.0f, 0);
        }
        else
        {
            ctx.gpu->SetViewFrameBuffer(view, kGpuInvalidHandle);
            // BGFX_CLEAR_NONE
            ctx.gpu->SetViewClear(view, 0, 0, 0, 0);
        }
        ctx.gpu->SetViewRect(view, 0, 0, (uint16_t)w, (uint16_t)h);
        ctx.gpu->SetVertexBuffer(0, geometry.fullscreen_vb);
        ctx.gpu->SetIndexBufferStatic(geometry.fullscreen_ib);
        // BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A
        ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000008ULL, 0);
        ctx.gpu->Submit(view, prog, 0, false);
    };

    GpuTextureHandle bloom_result_tex = textures.GetTextureIdx(0);
    if (bloom_enabled_ && bright_fb_ != kGpuInvalidHandle)
    {
        float bp[4] = {bloom_threshold_, 0.f, 0.f, 0.f};
        ctx.gpu->SetUniform(bloom_params_uniform_, bp, 1);
        ctx.gpu->SetTexture(0, hdr_tex_uniform_, hdr_color_tex_, 0xFFFFFFFF);
        submit_fs(kBrightView, bright_fb_, pp_w_, pp_h_, bright_prog);

        float bh[4] = {1.f / (float)pp_w_, 0.f, 0.f, 0.f};
        ctx.gpu->SetUniform(blur_params_uniform_, bh, 1);
        ctx.gpu->SetTexture(0, blur_tex_uniform_, ctx.gpu->GetTexture(bright_fb_, 0), 0xFFFFFFFF);
        submit_fs(kBlurHView, blur_a_fb_, pp_w_, pp_h_, blur_prog);

        float bv[4] = {0.f, 1.f / (float)pp_h_, 0.f, 0.f};
        ctx.gpu->SetUniform(blur_params_uniform_, bv, 1);
        ctx.gpu->SetTexture(0, blur_tex_uniform_, ctx.gpu->GetTexture(blur_a_fb_, 0), 0xFFFFFFFF);
        submit_fs(kBlurVView, blur_b_fb_, pp_w_, pp_h_, blur_prog);

        bloom_result_tex = ctx.gpu->GetTexture(blur_b_fb_, 0);
    }

    float tp[4] = {exposure_, bloom_enabled_ ? bloom_intensity_ : 0.f, 1.f / gamma_, 0.f};
    ctx.gpu->SetUniform(tonemap_params_uniform_, tp, 1);
    ctx.gpu->SetTexture(0, hdr_tex_uniform_, hdr_color_tex_, 0xFFFFFFFF);
    ctx.gpu->SetTexture(1, bloom_tex_uniform_, bloom_result_tex, 0xFFFFFFFF);
    submit_fs(kTonemapView, kGpuInvalidHandle, ctx.view_w, ctx.view_h, tonemap_prog);

    return KE_OK;
}

ke_result PostProcessPipeline::SetupSsao(RenderContext& ctx, 
                                         GpuProgramHandle& out_prepass_prog, 
                                         GpuProgramHandle& out_ssao_prog, 
                                         GpuProgramHandle& out_ssao_blur_prog)
{
    if (!ctx.gpu || !ctx.shader_provider) return KE_ERROR_RENDER;

    auto load_shader = [&](const char* name) -> GpuShaderHandle {
        const GpuMemoryBuffer* mem = ctx.shader_provider->LoadShaderBinary(ctx, name);
        if (!mem) return kGpuInvalidHandle;
        return ctx.gpu->CreateShader(mem);
    };

    auto load_prog = [&](const char *vs_name, const char *fs_name) -> GpuProgramHandle {
        auto v = load_shader(vs_name);
        auto f = load_shader(fs_name);
        if (v == kGpuInvalidHandle || f == kGpuInvalidHandle) return kGpuInvalidHandle;
        return ctx.gpu->CreateProgram(v, f, true);
    };

    out_prepass_prog   = load_prog("vs_prepass", "fs_prepass");
    out_ssao_prog      = load_prog("vs_screen",  "fs_ssao");
    out_ssao_blur_prog = load_prog("vs_screen",  "fs_ssao_blur");

    srand(42);
    auto rnd01 = []() -> float { return (float)rand() / (float)RAND_MAX; };
    auto rnd11 = []() -> float { return (float)rand() / (float)RAND_MAX * 2.f - 1.f; };

    for (uint32_t i = 0; i < kSsaoKernelSize; ++i)
    {
        float x = rnd11(), y = rnd11(), z = rnd01();
        float len = sqrtf(x*x + y*y + z*z);
        if (len < 0.0001f) { x = 0; y = 0; z = 1; len = 1; }
        x /= len; y /= len; z /= len;
        float scale = (float)i / (float)kSsaoKernelSize;
        scale = 0.1f + scale * scale * 0.9f;
        ssao_kernel_data_[i * 4 + 0] = x * scale;
        ssao_kernel_data_[i * 4 + 1] = y * scale;
        ssao_kernel_data_[i * 4 + 2] = z * scale;
        ssao_kernel_data_[i * 4 + 3] = 0.f;
    }

    uint8_t noise_pixels[4 * 4 * 4];
    for (int i = 0; i < 16; ++i)
    {
        float rx = rnd11(), ry = rnd11();
        float rlen = sqrtf(rx*rx + ry*ry);
        if (rlen > 0.0001f) { rx /= rlen; ry /= rlen; }
        noise_pixels[i * 4 + 0] = (uint8_t)((rx * 0.5f + 0.5f) * 255.f);
        noise_pixels[i * 4 + 1] = (uint8_t)((ry * 0.5f + 0.5f) * 255.f);
        noise_pixels[i * 4 + 2] = 128;
        noise_pixels[i * 4 + 3] = 255;
    }
    // BGFX_SAMPLER_POINT
    ssao_noise_tex_ = ctx.gpu->CreateTexture2D(4, 4, false, 1, 6 /*RGBA8*/, 0x0000000100000000ULL, ctx.gpu->Copy(noise_pixels, 64));

    s_gbuf_normal_u  = ctx.gpu->CreateUniform("s_gbufNormal",    GpuUniformType::Sampler, 1);
    s_gbuf_depth_u   = ctx.gpu->CreateUniform("s_gbufDepth",     GpuUniformType::Sampler, 1);
    s_ssao_noise_u_  = ctx.gpu->CreateUniform("s_ssaoNoise",     GpuUniformType::Sampler, 1);
    s_ssao_input_u_  = ctx.gpu->CreateUniform("s_ssaoInput",     GpuUniformType::Sampler, 1);
    s_ssao_blurred_u = ctx.gpu->CreateUniform("s_ssaoBlurred",   GpuUniformType::Sampler, 1);
    ssao_kernel_u_   = ctx.gpu->CreateUniform("u_ssaoKernel",    GpuUniformType::Vec4, kSsaoKernelSize);
    ssao_params_u_   = ctx.gpu->CreateUniform("u_ssaoParams",    GpuUniformType::Vec4, 1);
    ssao_proj_info_u_ = ctx.gpu->CreateUniform("u_ssaoProjInfo",  GpuUniformType::Vec4, 1);
    ssao_blur_params_u_ = ctx.gpu->CreateUniform("u_ssaoBlurParams", GpuUniformType::Vec4, 1);
    ssao_state_u     = ctx.gpu->CreateUniform("u_ssaoState",     GpuUniformType::Vec4, 1);

    GpuTextureHandle gbuf_texs[3] = {
        ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, 6 /*RGBA8*/, 0x0000100000000000ULL | 0x0000000100000000ULL, nullptr),
        ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, 15 /*R16F*/,  0x0000100000000000ULL | 0x0000000100000000ULL, nullptr),
        ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, 26 /*D24S8*/, 0x0000200000000000ULL, nullptr),
    };
    gbuf_fb_ = ctx.gpu->CreateFrameBuffer(3, gbuf_texs, true);
    gbuf_normal_tex_    = ctx.gpu->GetTexture(gbuf_fb_, 0);
    gbuf_lin_depth_tex_ = ctx.gpu->GetTexture(gbuf_fb_, 1);

    GpuTextureHandle ssao_raw_t = ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, 6 /*RGBA8*/, 0x0000100000000000ULL | 0x0000000100000000ULL, nullptr);
    ssao_raw_fb_  = ctx.gpu->CreateFrameBuffer(1, &ssao_raw_t, true);
    ssao_raw_tex_ = ctx.gpu->GetTexture(ssao_raw_fb_, 0);

    GpuTextureHandle ssao_blur_t = ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, 6 /*RGBA8*/, 0x0000100000000000ULL | 0x0000000100000000ULL, nullptr);
    ssao_blur_fb_  = ctx.gpu->CreateFrameBuffer(1, &ssao_blur_t, true);
    ssao_blur_tex_ = ctx.gpu->GetTexture(ssao_blur_fb_, 0);

    return KE_OK;
}

ke_result PostProcessPipeline::SubmitSsao(RenderContext& ctx, 
                                         const GeometryManager& geometry,
                                         const TextureManager& textures,
                                         GpuProgramHandle ssao_prog, 
                                         GpuProgramHandle ssao_blur_prog)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;
    if (!ssao_enabled_) return KE_OK;
    if (gbuf_normal_tex_ == kGpuInvalidHandle || ssao_raw_tex_ == kGpuInvalidHandle) return KE_OK;

    float ssao_params[4]    = {ssao_radius_, ssao_bias_, ssao_strength_, 0.f};
    float ssao_proj_info[4] = {ssao_proj_info_[0], ssao_proj_info_[1], 0.f, 0.f};

    ctx.gpu->SetUniform(ssao_kernel_u_,    ssao_kernel_data_, kSsaoKernelSize);
    ctx.gpu->SetUniform(ssao_params_u_,    ssao_params, 1);
    ctx.gpu->SetUniform(ssao_proj_info_u_, ssao_proj_info, 1);
    ctx.gpu->SetTexture(0, s_gbuf_normal_u, gbuf_normal_tex_, 0xFFFFFFFF);
    ctx.gpu->SetTexture(1, s_gbuf_depth_u,  gbuf_lin_depth_tex_, 0xFFFFFFFF);
    ctx.gpu->SetTexture(2, s_ssao_noise_u_,  ssao_noise_tex_, 0xFFFFFFFF);
    ctx.gpu->SetVertexBuffer(0, geometry.fullscreen_vb);
    ctx.gpu->SetIndexBufferStatic(geometry.fullscreen_ib);
    // BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A
    ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000008ULL, 0);
    ctx.gpu->Submit(kSsaoView, ssao_prog, 0, false);

    float blur_params[4] = { (ctx.view_w > 0) ? 1.f / (float)ctx.view_w : 0.f, (ctx.view_h > 0) ? 1.f / (float)ctx.view_h : 0.f, 0.f, 0.f };
    ctx.gpu->SetUniform(ssao_blur_params_u_, blur_params, 1);
    ctx.gpu->SetTexture(0, s_ssao_input_u_, ssao_raw_tex_, 0xFFFFFFFF);
    ctx.gpu->SetVertexBuffer(0, geometry.fullscreen_vb);
    ctx.gpu->SetIndexBufferStatic(geometry.fullscreen_ib);
    // BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A
    ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000008ULL, 0);
    ctx.gpu->Submit(kSsaoBlurView, ssao_blur_prog, 0, false);

    return KE_OK;
}

void PostProcessPipeline::Shutdown()
{
}

} // namespace kernel_engine::render::bgfx
