#include "PostProcessPipeline.hpp"
#include "BgfxRenderer.hpp"
#include "bgfx_interface.hh"
#include <fstream>
#include <vector>
#include <cmath>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result PostProcessPipeline::SetTonemapping(ke_bool enabled, float exposure, float gamma)
{
    if (enabled && hdr_fb_ == kInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    pp_enabled_ = (enabled != 0);
    exposure_   = exposure;
    gamma_      = gamma;
    return KE_OK;
}

ke_result PostProcessPipeline::SetBloom(ke_bool enabled, float threshold, float intensity)
{
    if (enabled && bright_fb_ == kInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    bloom_enabled_   = (enabled != 0);
    bloom_threshold_ = threshold;
    bloom_intensity_ = intensity;
    return KE_OK;
}

ke_result PostProcessPipeline::SetSsao(ke_bool enabled, float radius, float bias, float strength)
{
    ssao_enabled_  = (enabled != 0);
    ssao_radius_   = radius;
    ssao_bias_     = bias;
    ssao_strength_ = strength;
    return KE_OK;
}

ke_result PostProcessPipeline::SetupPostProcess()
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    
    auto load_shader = [&](const char *name) -> ::bgfx::ShaderHandle {
        std::string path = renderer->shader_path_ + "/" + name + ".bin";
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open()) return ::bgfx::ShaderHandle{::bgfx::kInvalidHandle};
        auto size = (uint32_t)file.tellg();
        file.seekg(0);
        const ::bgfx::Memory *mem = renderer->bgfx_->Alloc(size + 1);
        file.read(reinterpret_cast<char *>(mem->data), size);
        mem->data[size] = '\0';
        return renderer->bgfx_->CreateShader(mem);
    };

    auto load_pp_program = [&](const char *vs_name, const char *fs_name) -> uint16_t {
        ::bgfx::ShaderHandle vs = load_shader(vs_name);
        ::bgfx::ShaderHandle fs = load_shader(fs_name);
        if (!::bgfx::isValid(vs) || !::bgfx::isValid(fs))
        {
            if (::bgfx::isValid(vs)) renderer->bgfx_->Destroy(vs);
            if (::bgfx::isValid(fs)) renderer->bgfx_->Destroy(fs);
            return kInvalidHandle;
        }
        ::bgfx::ProgramHandle prog = renderer->bgfx_->CreateProgram(vs, fs, true);
        return ::bgfx::isValid(prog) ? prog.idx : kInvalidHandle;
    };

    renderer->bright_pass_program_ = load_pp_program("vs_fullscreen", "fs_bright_pass");
    renderer->blur_program_        = load_pp_program("vs_fullscreen", "fs_blur");
    renderer->tonemap_program_     = load_pp_program("vs_fullscreen", "fs_tonemap");

    if (renderer->bright_pass_program_ == kInvalidHandle ||
        renderer->blur_program_        == kInvalidHandle ||
        renderer->tonemap_program_     == kInvalidHandle)
    {
        return KE_OK;
    }

    ::bgfx::VertexLayout pos3;
    pos3.begin().add(::bgfx::Attrib::Position, 3, ::bgfx::AttribType::Float).end();
    static const float kFSVerts[9] = {-1.f,-1.f,0.f,  3.f,-1.f,0.f,  -1.f,3.f,0.f};
    static const uint16_t kFSIdx[3] = {0, 1, 2};
    renderer->fullscreen_vb_ = renderer->bgfx_->CreateVertexBuffer(renderer->bgfx_->Copy(kFSVerts, sizeof(kFSVerts)), pos3).idx;
    renderer->fullscreen_ib_ = renderer->bgfx_->CreateIndexBuffer(renderer->bgfx_->Copy(kFSIdx, sizeof(kFSIdx))).idx;

    ::bgfx::TextureHandle hdr_color = renderer->bgfx_->CreateTexture2D(
        (uint16_t)renderer->view_w_, (uint16_t)renderer->view_h_, false, 1,
        ::bgfx::TextureFormat::RGBA16F, BGFX_TEXTURE_RT);
    ::bgfx::TextureHandle hdr_depth = renderer->bgfx_->CreateTexture2D(
        (uint16_t)renderer->view_w_, (uint16_t)renderer->view_h_, false, 1,
        ::bgfx::TextureFormat::D24, BGFX_TEXTURE_RT_WRITE_ONLY);

    if (!::bgfx::isValid(hdr_color) || !::bgfx::isValid(hdr_depth))
    {
        if (::bgfx::isValid(hdr_color)) renderer->bgfx_->Destroy(hdr_color);
        if (::bgfx::isValid(hdr_depth)) renderer->bgfx_->Destroy(hdr_depth);
        return KE_OK;
    }

    ::bgfx::TextureHandle hdr_attachments[2] = {hdr_color, hdr_depth};
    ::bgfx::FrameBufferHandle hdr_fb = renderer->bgfx_->CreateFrameBuffer(2, hdr_attachments, false);
    if (!::bgfx::isValid(hdr_fb))
    {
        renderer->bgfx_->Destroy(hdr_color);
        renderer->bgfx_->Destroy(hdr_depth);
        return KE_OK;
    }
    hdr_fb_        = hdr_fb.idx;
    hdr_color_tex_ = hdr_color.idx;
    renderer->bgfx_->Destroy(hdr_depth);

    pp_w_ = (renderer->view_w_ + 1) / 2;
    pp_h_ = (renderer->view_h_ + 1) / 2;

    auto make_color_fb = [&](int w, int h) -> uint16_t {
        ::bgfx::TextureHandle tex = renderer->bgfx_->CreateTexture2D(
            (uint16_t)w, (uint16_t)h, false, 1,
            ::bgfx::TextureFormat::RGBA16F, BGFX_TEXTURE_RT);
        if (!::bgfx::isValid(tex)) return kInvalidHandle;
        ::bgfx::FrameBufferHandle fb = renderer->bgfx_->CreateFrameBuffer(1, &tex, true);
        return ::bgfx::isValid(fb) ? fb.idx : kInvalidHandle;
    };

    bright_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_a_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_b_fb_ = make_color_fb(pp_w_, pp_h_);

    hdr_tex_uniform_       = renderer->bgfx_->CreateUniform("s_hdrTex",       ::bgfx::UniformType::Sampler).idx;
    bloom_tex_uniform_     = renderer->bgfx_->CreateUniform("s_bloomTex",     ::bgfx::UniformType::Sampler).idx;
    blur_tex_uniform_      = renderer->bgfx_->CreateUniform("s_blurTex",      ::bgfx::UniformType::Sampler).idx;
    bloom_params_uniform_  = renderer->bgfx_->CreateUniform("u_bloomParams",  ::bgfx::UniformType::Vec4).idx;
    blur_params_uniform_   = renderer->bgfx_->CreateUniform("u_blurParams",   ::bgfx::UniformType::Vec4).idx;
    tonemap_params_uniform_= renderer->bgfx_->CreateUniform("u_tonemapParams",::bgfx::UniformType::Vec4).idx;

    return KE_OK;
}

ke_result PostProcessPipeline::SubmitPostProcess()
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    
    auto submit_fs = [&](uint8_t view, uint16_t fb, int w, int h, uint16_t prog) {
        if (fb != kInvalidHandle)
        {
            renderer->bgfx_->SetViewFrameBuffer(view, ::bgfx::FrameBufferHandle{fb});
            renderer->bgfx_->SetViewClear(view, BGFX_CLEAR_COLOR, 0x000000ff, 1.0f, 0);
        }
        else
        {
            renderer->bgfx_->SetViewFrameBuffer(view, ::bgfx::FrameBufferHandle{::bgfx::kInvalidHandle});
            renderer->bgfx_->SetViewClear(view, BGFX_CLEAR_NONE);
        }
        renderer->bgfx_->SetViewRect(view, 0, 0, (uint16_t)w, (uint16_t)h);
        renderer->bgfx_->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{renderer->fullscreen_vb_});
        renderer->bgfx_->SetIndexBuffer(::bgfx::IndexBufferHandle{renderer->fullscreen_ib_});
        renderer->bgfx_->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A);
        renderer->bgfx_->Submit(view, ::bgfx::ProgramHandle{prog});
    };

    uint16_t bloom_result_tex = renderer->textures_[0].idx;
    if (bloom_enabled_ && bright_fb_ != kInvalidHandle)
    {
        float bp[4] = {bloom_threshold_, 0.f, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{bloom_params_uniform_}, bp);
        renderer->bgfx_->SetTexture(0, ::bgfx::UniformHandle{hdr_tex_uniform_},
            ::bgfx::TextureHandle{hdr_color_tex_});
        submit_fs(kBrightView, bright_fb_, pp_w_, pp_h_, renderer->bright_pass_program_);

        float bh[4] = {1.f / (float)pp_w_, 0.f, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{blur_params_uniform_}, bh);
        renderer->bgfx_->SetTexture(0, ::bgfx::UniformHandle{blur_tex_uniform_},
            renderer->bgfx_->GetTexture(::bgfx::FrameBufferHandle{bright_fb_}));
        submit_fs(kBlurHView, blur_a_fb_, pp_w_, pp_h_, renderer->blur_program_);

        float bv[4] = {0.f, 1.f / (float)pp_h_, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{blur_params_uniform_}, bv);
        renderer->bgfx_->SetTexture(0, ::bgfx::UniformHandle{blur_tex_uniform_},
            renderer->bgfx_->GetTexture(::bgfx::FrameBufferHandle{blur_a_fb_}));
        submit_fs(kBlurVView, blur_b_fb_, pp_w_, pp_h_, renderer->blur_program_);

        bloom_result_tex = renderer->bgfx_->GetTexture(::bgfx::FrameBufferHandle{blur_b_fb_}).idx;
    }

    float tp[4] = {exposure_, bloom_enabled_ ? bloom_intensity_ : 0.f, 1.f / gamma_, 0.f};
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{tonemap_params_uniform_}, tp);
    renderer->bgfx_->SetTexture(0, ::bgfx::UniformHandle{hdr_tex_uniform_},
        ::bgfx::TextureHandle{hdr_color_tex_});
    renderer->bgfx_->SetTexture(1, ::bgfx::UniformHandle{bloom_tex_uniform_},
        ::bgfx::TextureHandle{bloom_result_tex});
    submit_fs(kTonemapView, kInvalidHandle, renderer->view_w_, renderer->view_h_, renderer->tonemap_program_);

    return KE_OK;
}

ke_result PostProcessPipeline::SetupSsao()
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    auto load_shader = [&](const char *name) -> ::bgfx::ShaderHandle {
        std::string path = renderer->shader_path_ + "/" + name + ".bin";
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open()) return ::bgfx::ShaderHandle{::bgfx::kInvalidHandle};
        auto size = file.tellg();
        file.seekg(0);
        const ::bgfx::Memory *mem = renderer->bgfx_->Alloc((uint32_t)size);
        file.read(reinterpret_cast<char *>(mem->data), size);
        return renderer->bgfx_->CreateShader(mem);
    };

    auto load_program = [&](const char *vs, const char *fs) -> uint16_t {
        auto v = load_shader(vs);
        auto f = load_shader(fs);
        if (!::bgfx::isValid(v) || !::bgfx::isValid(f)) {
            if (::bgfx::isValid(v)) renderer->bgfx_->Destroy(v);
            if (::bgfx::isValid(f)) renderer->bgfx_->Destroy(f);
            return kInvalidHandle;
        }
        return renderer->bgfx_->CreateProgram(v, f, true).idx;
    };

    renderer->prepass_program_    = load_program("vs_prepass",   "fs_prepass");
    renderer->ssao_program_       = load_program("vs_screen",    "fs_ssao");
    renderer->ssao_blur_program_  = load_program("vs_screen",    "fs_ssao_blur");

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
    ssao_noise_tex_ = renderer->bgfx_->CreateTexture2D(
        4, 4, false, 1, ::bgfx::TextureFormat::RGBA8,
        BGFX_SAMPLER_POINT,
        renderer->bgfx_->Copy(noise_pixels, sizeof(noise_pixels))).idx;

    s_gbuf_normal_u_    = renderer->bgfx_->CreateUniform("s_gbufNormal",    ::bgfx::UniformType::Sampler).idx;
    s_gbuf_depth_u_     = renderer->bgfx_->CreateUniform("s_gbufDepth",     ::bgfx::UniformType::Sampler).idx;
    s_ssao_noise_u_     = renderer->bgfx_->CreateUniform("s_ssaoNoise",     ::bgfx::UniformType::Sampler).idx;
    s_ssao_input_u_     = renderer->bgfx_->CreateUniform("s_ssaoInput",     ::bgfx::UniformType::Sampler).idx;
    s_ssao_blurred_u_   = renderer->bgfx_->CreateUniform("s_ssaoBlurred",   ::bgfx::UniformType::Sampler).idx;
    ssao_kernel_u_      = renderer->bgfx_->CreateUniform("u_ssaoKernel",    ::bgfx::UniformType::Vec4, kSsaoKernelSize).idx;
    ssao_params_u_      = renderer->bgfx_->CreateUniform("u_ssaoParams",    ::bgfx::UniformType::Vec4).idx;
    ssao_proj_info_u_   = renderer->bgfx_->CreateUniform("u_ssaoProjInfo",  ::bgfx::UniformType::Vec4).idx;
    ssao_blur_params_u_ = renderer->bgfx_->CreateUniform("u_ssaoBlurParams",::bgfx::UniformType::Vec4).idx;
    ssao_state_u_       = renderer->bgfx_->CreateUniform("u_ssaoState",     ::bgfx::UniformType::Vec4).idx;

    ::bgfx::TextureHandle gbuf_texs[3] = {
        renderer->bgfx_->CreateTexture2D((uint16_t)renderer->view_w_, (uint16_t)renderer->view_h_, false, 1,
            ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT),
        renderer->bgfx_->CreateTexture2D((uint16_t)renderer->view_w_, (uint16_t)renderer->view_h_, false, 1,
            ::bgfx::TextureFormat::R16F,  BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT),
        renderer->bgfx_->CreateTexture2D((uint16_t)renderer->view_w_, (uint16_t)renderer->view_h_, false, 1,
            ::bgfx::TextureFormat::D24S8, BGFX_TEXTURE_RT_WRITE_ONLY),
    };
    gbuf_fb_ = renderer->bgfx_->CreateFrameBuffer(3, gbuf_texs, true).idx;
    gbuf_normal_tex_    = renderer->bgfx_->GetTexture(::bgfx::FrameBufferHandle{gbuf_fb_}, 0).idx;
    gbuf_lin_depth_tex_ = renderer->bgfx_->GetTexture(::bgfx::FrameBufferHandle{gbuf_fb_}, 1).idx;

    ::bgfx::TextureHandle ssao_raw_t = renderer->bgfx_->CreateTexture2D(
        (uint16_t)renderer->view_w_, (uint16_t)renderer->view_h_, false, 1,
        ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT);
    ssao_raw_fb_  = renderer->bgfx_->CreateFrameBuffer(1, &ssao_raw_t, true).idx;
    ssao_raw_tex_ = renderer->bgfx_->GetTexture(::bgfx::FrameBufferHandle{ssao_raw_fb_}).idx;

    ::bgfx::TextureHandle ssao_blur_t = renderer->bgfx_->CreateTexture2D(
        (uint16_t)renderer->view_w_, (uint16_t)renderer->view_h_, false, 1,
        ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT);
    ssao_blur_fb_  = renderer->bgfx_->CreateFrameBuffer(1, &ssao_blur_t, true).idx;
    ssao_blur_tex_ = renderer->bgfx_->GetTexture(::bgfx::FrameBufferHandle{ssao_blur_fb_}).idx;

    return KE_OK;
}

ke_result PostProcessPipeline::SubmitSsao()
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    if (!ssao_enabled_) return KE_OK;
    if (gbuf_normal_tex_ == kInvalidHandle || ssao_raw_tex_ == kInvalidHandle) return KE_OK;

    float ssao_params[4]    = {ssao_radius_, ssao_bias_, ssao_strength_, 0.f};
    float ssao_proj_info[4] = {renderer->ssao_proj_info_[0], renderer->ssao_proj_info_[1], 0.f, 0.f};

    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{ssao_kernel_u_},    ssao_kernel_data_, kSsaoKernelSize);
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{ssao_params_u_},    ssao_params);
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{ssao_proj_info_u_}, ssao_proj_info);
    renderer->bgfx_->SetTexture(0, ::bgfx::UniformHandle{s_gbuf_normal_u_}, ::bgfx::TextureHandle{gbuf_normal_tex_});
    renderer->bgfx_->SetTexture(1, ::bgfx::UniformHandle{s_gbuf_depth_u_},  ::bgfx::TextureHandle{gbuf_lin_depth_tex_});
    renderer->bgfx_->SetTexture(2, ::bgfx::UniformHandle{s_ssao_noise_u_},  ::bgfx::TextureHandle{ssao_noise_tex_});
    renderer->bgfx_->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{renderer->fullscreen_vb_});
    renderer->bgfx_->SetIndexBuffer(::bgfx::IndexBufferHandle{renderer->fullscreen_ib_});
    renderer->bgfx_->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A);
    renderer->bgfx_->Submit(kSsaoView, ::bgfx::ProgramHandle{renderer->ssao_program_});

    float blur_params[4] = {
        (renderer->view_w_ > 0) ? 1.f / (float)renderer->view_w_ : 0.f,
        (renderer->view_h_ > 0) ? 1.f / (float)renderer->view_h_ : 0.f,
        0.f, 0.f
    };
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{ssao_blur_params_u_}, blur_params);
    renderer->bgfx_->SetTexture(0, ::bgfx::UniformHandle{s_ssao_input_u_}, ::bgfx::TextureHandle{ssao_raw_tex_});
    renderer->bgfx_->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{renderer->fullscreen_vb_});
    renderer->bgfx_->SetIndexBuffer(::bgfx::IndexBufferHandle{renderer->fullscreen_ib_});
    renderer->bgfx_->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A);
    renderer->bgfx_->Submit(kSsaoBlurView, ::bgfx::ProgramHandle{renderer->ssao_blur_program_});

    return KE_OK;
}

} // namespace kernel_engine::render::bgfx
