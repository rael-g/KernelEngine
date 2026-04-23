#include "post_process_pipeline.hpp"
#include "render_context.hpp"
#include "geometry_manager.hpp"
#include "texture_manager.hpp"
#include "shader_provider.hpp"
#include "gpu_device.hpp"
#include <bgfx/bgfx.h>
#include <vector>
#include <cmath>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result PostProcessPipeline::SetTonemapping(RenderContext& ctx, ke_bool enabled, float exposure, float gamma)
{
    if (enabled && hdr_fb_ == kInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    pp_enabled_ = (enabled != 0);
    exposure_   = exposure;
    gamma_      = gamma;
    return KE_OK;
}

ke_result PostProcessPipeline::SetBloom(RenderContext& ctx, ke_bool enabled, float threshold, float intensity)
{
    if (enabled && bright_fb_ == kInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
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
                                                uint16_t& out_bright_prog, 
                                                uint16_t& out_blur_prog, 
                                                uint16_t& out_tonemap_prog)
{
    if (!ctx.gpu || !ctx.shader_provider) return KE_ERROR_RENDER;

    auto load_shader = [&](const char* name) -> ::bgfx::ShaderHandle {
        const ::bgfx::Memory* mem = ctx.shader_provider->LoadShaderBinary(ctx, name);
        if (!mem) return { ::bgfx::kInvalidHandle };
        return ctx.gpu->CreateShader(mem);
    };

    auto load_pp_program = [&](const char *vs_name, const char *fs_name) -> uint16_t {
        ::bgfx::ShaderHandle vs = load_shader(vs_name);
        ::bgfx::ShaderHandle fs = load_shader(fs_name);
        if (!::bgfx::isValid(vs) || !::bgfx::isValid(fs))
        {
            if (::bgfx::isValid(vs)) ctx.gpu->Destroy(vs);
            if (::bgfx::isValid(fs)) ctx.gpu->Destroy(fs);
            return kInvalidHandle;
        }
        ::bgfx::ProgramHandle prog = ctx.gpu->CreateProgram(vs, fs, true);
        return ::bgfx::isValid(prog) ? prog.idx : kInvalidHandle;
    };

    out_bright_prog = load_pp_program("vs_fullscreen", "fs_bright_pass");
    out_blur_prog   = load_pp_program("vs_fullscreen", "fs_blur");
    out_tonemap_prog = load_pp_program("vs_fullscreen", "fs_tonemap");

    if (out_bright_prog == kInvalidHandle || out_blur_prog == kInvalidHandle || out_tonemap_prog == kInvalidHandle)
        return KE_OK;

    ::bgfx::VertexLayout pos3;
    pos3.begin().add(::bgfx::Attrib::Position, 3, ::bgfx::AttribType::Float).end();
    static const float kFSVerts[9] = {-1.f,-1.f,0.f,  3.f,-1.f,0.f,  -1.f,3.f,0.f};
    static const uint16_t kFSIdx[3] = {0, 1, 2};
    geometry.fullscreen_vb = ctx.gpu->CreateVertexBuffer(ctx.gpu->Copy(kFSVerts, sizeof(kFSVerts)), pos3).idx;
    geometry.fullscreen_ib = ctx.gpu->CreateIndexBuffer(ctx.gpu->Copy(kFSIdx, sizeof(kFSIdx))).idx;

    ::bgfx::TextureHandle hdr_color = ctx.gpu->CreateTexture2D(
        (uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1,
        ::bgfx::TextureFormat::RGBA16F, BGFX_TEXTURE_RT, nullptr);
    ::bgfx::TextureHandle hdr_depth = ctx.gpu->CreateTexture2D(
        (uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1,
        ::bgfx::TextureFormat::D24, BGFX_TEXTURE_RT_WRITE_ONLY, nullptr);

    if (!::bgfx::isValid(hdr_color) || !::bgfx::isValid(hdr_depth)) return KE_OK;

    ::bgfx::TextureHandle hdr_attachments[2] = {hdr_color, hdr_depth};
    ::bgfx::FrameBufferHandle hdr_fb = ctx.gpu->CreateFrameBuffer(2, hdr_attachments, false);
    if (!::bgfx::isValid(hdr_fb)) return KE_OK;

    hdr_fb_        = hdr_fb.idx;
    hdr_color_tex_ = hdr_color.idx;
    ctx.gpu->Destroy(hdr_depth);

    pp_w_ = (ctx.view_w + 1) / 2;
    pp_h_ = (ctx.view_h + 1) / 2;

    auto make_color_fb = [&](int w, int h) -> uint16_t {
        ::bgfx::TextureHandle tex = ctx.gpu->CreateTexture2D(
            (uint16_t)w, (uint16_t)h, false, 1,
            ::bgfx::TextureFormat::RGBA16F, BGFX_TEXTURE_RT, nullptr);
        if (!::bgfx::isValid(tex)) return kInvalidHandle;
        ::bgfx::FrameBufferHandle fb = ctx.gpu->CreateFrameBuffer(1, &tex, true);
        return ::bgfx::isValid(fb) ? fb.idx : kInvalidHandle;
    };

    bright_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_a_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_b_fb_ = make_color_fb(pp_w_, pp_h_);

    hdr_tex_uniform_       = ctx.gpu->CreateUniform("s_hdrTex",       ::bgfx::UniformType::Sampler, 1).idx;
    bloom_tex_uniform_     = ctx.gpu->CreateUniform("s_bloomTex",     ::bgfx::UniformType::Sampler, 1).idx;
    blur_tex_uniform_      = ctx.gpu->CreateUniform("s_blurTex",      ::bgfx::UniformType::Sampler, 1).idx;
    bloom_params_uniform_  = ctx.gpu->CreateUniform("u_bloomParams",  ::bgfx::UniformType::Vec4, 1).idx;
    blur_params_uniform_   = ctx.gpu->CreateUniform("u_blurParams",   ::bgfx::UniformType::Vec4, 1).idx;
    tonemap_params_uniform_= ctx.gpu->CreateUniform("u_tonemapParams",::bgfx::UniformType::Vec4, 1).idx;

    return KE_OK;
}

ke_result PostProcessPipeline::SubmitPostProcess(RenderContext& ctx, 
                                                const GeometryManager& geometry,
                                                const TextureManager& textures,
                                                uint16_t bright_prog, 
                                                uint16_t blur_prog, 
                                                uint16_t tonemap_prog)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;

    auto submit_fs = [&](uint8_t view, uint16_t fb, int w, int h, uint16_t prog) {
        if (fb != kInvalidHandle)
        {
            ctx.gpu->SetViewFrameBuffer(view, ::bgfx::FrameBufferHandle{fb});
            ctx.gpu->SetViewClear(view, BGFX_CLEAR_COLOR, 0x000000ff, 1.0f, 0);
        }
        else
        {
            ctx.gpu->SetViewFrameBuffer(view, ::bgfx::FrameBufferHandle{::bgfx::kInvalidHandle});
            ctx.gpu->SetViewClear(view, BGFX_CLEAR_NONE, 0, 0, 0);
        }
        ctx.gpu->SetViewRect(view, 0, 0, (uint16_t)w, (uint16_t)h);
        ctx.gpu->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{geometry.fullscreen_vb});
        ctx.gpu->SetIndexBuffer(::bgfx::IndexBufferHandle{geometry.fullscreen_ib});
        ctx.gpu->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A, 0);
        ctx.gpu->Submit(view, ::bgfx::ProgramHandle{prog}, 0, false);
    };

    uint16_t bloom_result_tex = textures.GetTextureIdx(0);
    if (bloom_enabled_ && bright_fb_ != kInvalidHandle)
    {
        float bp[4] = {bloom_threshold_, 0.f, 0.f, 0.f};
        ctx.gpu->SetUniform(::bgfx::UniformHandle{bloom_params_uniform_}, bp, 1);
        ctx.gpu->SetTexture(0, ::bgfx::UniformHandle{hdr_tex_uniform_}, ::bgfx::TextureHandle{hdr_color_tex_}, 0xFFFFFFFF);
        submit_fs(kBrightView, bright_fb_, pp_w_, pp_h_, bright_prog);

        float bh[4] = {1.f / (float)pp_w_, 0.f, 0.f, 0.f};
        ctx.gpu->SetUniform(::bgfx::UniformHandle{blur_params_uniform_}, bh, 1);
        ctx.gpu->SetTexture(0, ::bgfx::UniformHandle{blur_tex_uniform_}, ctx.gpu->GetTexture(::bgfx::FrameBufferHandle{bright_fb_}, 0), 0xFFFFFFFF);
        submit_fs(kBlurHView, blur_a_fb_, pp_w_, pp_h_, blur_prog);

        float bv[4] = {0.f, 1.f / (float)pp_h_, 0.f, 0.f};
        ctx.gpu->SetUniform(::bgfx::UniformHandle{blur_params_uniform_}, bv, 1);
        ctx.gpu->SetTexture(0, ::bgfx::UniformHandle{blur_tex_uniform_}, ctx.gpu->GetTexture(::bgfx::FrameBufferHandle{blur_a_fb_}, 0), 0xFFFFFFFF);
        submit_fs(kBlurVView, blur_b_fb_, pp_w_, pp_h_, blur_prog);

        bloom_result_tex = ctx.gpu->GetTexture(::bgfx::FrameBufferHandle{blur_b_fb_}, 0).idx;
    }

    float tp[4] = {exposure_, bloom_enabled_ ? bloom_intensity_ : 0.f, 1.f / gamma_, 0.f};
    ctx.gpu->SetUniform(::bgfx::UniformHandle{tonemap_params_uniform_}, tp, 1);
    ctx.gpu->SetTexture(0, ::bgfx::UniformHandle{hdr_tex_uniform_}, ::bgfx::TextureHandle{hdr_color_tex_}, 0xFFFFFFFF);
    ctx.gpu->SetTexture(1, ::bgfx::UniformHandle{bloom_tex_uniform_}, ::bgfx::TextureHandle{bloom_result_tex}, 0xFFFFFFFF);
    submit_fs(kTonemapView, kInvalidHandle, ctx.view_w, ctx.view_h, tonemap_prog);

    return KE_OK;
}

ke_result PostProcessPipeline::SetupSsao(RenderContext& ctx, 
                                         uint16_t& out_prepass_prog, 
                                         uint16_t& out_ssao_prog, 
                                         uint16_t& out_ssao_blur_prog)
{
    if (!ctx.gpu || !ctx.shader_provider) return KE_ERROR_RENDER;

    auto load_shader = [&](const char* name) -> ::bgfx::ShaderHandle {
        const ::bgfx::Memory* mem = ctx.shader_provider->LoadShaderBinary(ctx, name);
        if (!mem) return { ::bgfx::kInvalidHandle };
        return ctx.gpu->CreateShader(mem);
    };

    auto load_prog = [&](const char *vs_name, const char *fs_name) -> uint16_t {
        auto v = load_shader(vs_name);
        auto f = load_shader(fs_name);
        if (!::bgfx::isValid(v) || !::bgfx::isValid(f)) return kInvalidHandle;
        return ctx.gpu->CreateProgram(v, f, true).idx;
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
    ssao_noise_tex_ = ctx.gpu->CreateTexture2D(4, 4, false, 1, ::bgfx::TextureFormat::RGBA8, BGFX_SAMPLER_POINT, ctx.gpu->Copy(noise_pixels, 64)).idx;

    s_gbuf_normal_u  = ctx.gpu->CreateUniform("s_gbufNormal",    ::bgfx::UniformType::Sampler, 1).idx;
    s_gbuf_depth_u   = ctx.gpu->CreateUniform("s_gbufDepth",     ::bgfx::UniformType::Sampler, 1).idx;
    s_ssao_noise_u_  = ctx.gpu->CreateUniform("s_ssaoNoise",     ::bgfx::UniformType::Sampler, 1).idx;
    s_ssao_input_u_  = ctx.gpu->CreateUniform("s_ssaoInput",     ::bgfx::UniformType::Sampler, 1).idx;
    s_ssao_blurred_u = ctx.gpu->CreateUniform("s_ssaoBlurred",   ::bgfx::UniformType::Sampler, 1).idx;
    ssao_kernel_u_   = ctx.gpu->CreateUniform("u_ssaoKernel",    ::bgfx::UniformType::Vec4, kSsaoKernelSize).idx;
    ssao_params_u_   = ctx.gpu->CreateUniform("u_ssaoParams",    ::bgfx::UniformType::Vec4, 1).idx;
    ssao_proj_info_u_ = ctx.gpu->CreateUniform("u_ssaoProjInfo",  ::bgfx::UniformType::Vec4, 1).idx;
    ssao_blur_params_u_ = ctx.gpu->CreateUniform("u_ssaoBlurParams",::bgfx::UniformType::Vec4, 1).idx;
    ssao_state_u     = ctx.gpu->CreateUniform("u_ssaoState",     ::bgfx::UniformType::Vec4, 1).idx;

    ::bgfx::TextureHandle gbuf_texs[3] = {
        ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT, nullptr),
        ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, ::bgfx::TextureFormat::R16F,  BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT, nullptr),
        ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, ::bgfx::TextureFormat::D24S8, BGFX_TEXTURE_RT_WRITE_ONLY, nullptr),
    };
    gbuf_fb_ = ctx.gpu->CreateFrameBuffer(3, gbuf_texs, true).idx;
    gbuf_normal_tex_    = ctx.gpu->GetTexture(::bgfx::FrameBufferHandle{gbuf_fb_}, 0).idx;
    gbuf_lin_depth_tex_ = ctx.gpu->GetTexture(::bgfx::FrameBufferHandle{gbuf_fb_}, 1).idx;

    ::bgfx::TextureHandle ssao_raw_t = ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT, nullptr);
    ssao_raw_fb_  = ctx.gpu->CreateFrameBuffer(1, &ssao_raw_t, true).idx;
    ssao_raw_tex_ = ctx.gpu->GetTexture(::bgfx::FrameBufferHandle{ssao_raw_fb_}, 0).idx;

    ::bgfx::TextureHandle ssao_blur_t = ctx.gpu->CreateTexture2D((uint16_t)ctx.view_w, (uint16_t)ctx.view_h, false, 1, ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT, nullptr);
    ssao_blur_fb_  = ctx.gpu->CreateFrameBuffer(1, &ssao_blur_t, true).idx;
    ssao_blur_tex_ = ctx.gpu->GetTexture(::bgfx::FrameBufferHandle{ssao_blur_fb_}, 0).idx;

    return KE_OK;
}

ke_result PostProcessPipeline::SubmitSsao(RenderContext& ctx, 
                                         const GeometryManager& geometry,
                                         const TextureManager& textures,
                                         uint16_t ssao_prog, 
                                         uint16_t ssao_blur_prog)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;
    if (!ssao_enabled_) return KE_OK;
    if (gbuf_normal_tex_ == kInvalidHandle || ssao_raw_tex_ == kInvalidHandle) return KE_OK;

    float ssao_params[4]    = {ssao_radius_, ssao_bias_, ssao_strength_, 0.f};
    float ssao_proj_info[4] = {ssao_proj_info_[0], ssao_proj_info_[1], 0.f, 0.f};

    ctx.gpu->SetUniform(::bgfx::UniformHandle{ssao_kernel_u_},    ssao_kernel_data_, kSsaoKernelSize);
    ctx.gpu->SetUniform(::bgfx::UniformHandle{ssao_params_u_},    ssao_params, 1);
    ctx.gpu->SetUniform(::bgfx::UniformHandle{ssao_proj_info_u_}, ssao_proj_info, 1);
    ctx.gpu->SetTexture(0, ::bgfx::UniformHandle{s_gbuf_normal_u}, ::bgfx::TextureHandle{gbuf_normal_tex_}, 0xFFFFFFFF);
    ctx.gpu->SetTexture(1, ::bgfx::UniformHandle{s_gbuf_depth_u},  ::bgfx::TextureHandle{gbuf_lin_depth_tex_}, 0xFFFFFFFF);
    ctx.gpu->SetTexture(2, ::bgfx::UniformHandle{s_ssao_noise_u_},  ::bgfx::TextureHandle{ssao_noise_tex_}, 0xFFFFFFFF);
    ctx.gpu->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{geometry.fullscreen_vb});
    ctx.gpu->SetIndexBuffer(::bgfx::IndexBufferHandle{geometry.fullscreen_ib});
    ctx.gpu->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A, 0);
    ctx.gpu->Submit(kSsaoView, ::bgfx::ProgramHandle{ssao_prog}, 0, false);

    float blur_params[4] = { (ctx.view_w > 0) ? 1.f / (float)ctx.view_w : 0.f, (ctx.view_h > 0) ? 1.f / (float)ctx.view_h : 0.f, 0.f, 0.f };
    ctx.gpu->SetUniform(::bgfx::UniformHandle{ssao_blur_params_u_}, blur_params, 1);
    ctx.gpu->SetTexture(0, ::bgfx::UniformHandle{s_ssao_input_u_}, ::bgfx::TextureHandle{ssao_raw_tex_}, 0xFFFFFFFF);
    ctx.gpu->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{geometry.fullscreen_vb});
    ctx.gpu->SetIndexBuffer(::bgfx::IndexBufferHandle{geometry.fullscreen_ib});
    ctx.gpu->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A, 0);
    ctx.gpu->Submit(kSsaoBlurView, ::bgfx::ProgramHandle{ssao_blur_prog}, 0, false);

    return KE_OK;
}

void PostProcessPipeline::Shutdown()
{
    // GPU device handles cleanup
}

} // namespace kernel_engine::render::bgfx
