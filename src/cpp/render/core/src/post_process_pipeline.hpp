#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::core
{

struct RenderContext;
class GeometryManager;
class TextureManager;

/**
 * @brief Agnostic post-processing pipeline (HDR, Bloom, SSAO, Tonemapping).
 */
class PostProcessPipeline
{
public:
    ke_result SetupPostProcess(RenderContext& ctx, 
                               GeometryManager& geometry,
                               render::GpuProgramHandle& out_bright_prog, 
                               render::GpuProgramHandle& out_blur_prog, 
                               render::GpuProgramHandle& out_tonemap_prog);

    ke_result SetupSsao(RenderContext& ctx, render::GpuProgramHandle& out_prepass, render::GpuProgramHandle& out_ssao, render::GpuProgramHandle& out_ssao_blur);

    ke_result SetTonemapping(RenderContext& ctx, ke_bool enabled, float exposure, float gamma);
    ke_result SetBloom(RenderContext& ctx, ke_bool enabled, float threshold, float intensity);
    ke_result SetSsao(RenderContext& ctx, ke_bool enabled, float radius, float bias, float strength);

    void SubmitPostProcess(RenderContext& ctx, GeometryManager& geom, TextureManager& tex, render::GpuProgramHandle bright, render::GpuProgramHandle blur, render::GpuProgramHandle tone);
    void SubmitSsao(RenderContext& ctx, GeometryManager& geom, TextureManager& tex, render::GpuProgramHandle ssao, render::GpuProgramHandle ssao_blur);

    void Shutdown();

    bool IsSsaoEnabled() const { return ssao_enabled_; }
    bool IsTonemapEnabled() const { return pp_enabled_; }
    render::GpuFrameBufferHandle GetGbufFb() const { return gbuf_fb_; }
    render::GpuFrameBufferHandle GetHdrFb() const { return hdr_fb_; }

    render::GpuFrameBufferHandle gbuf_fb_     = render::kGpuInvalidHandle;
    render::GpuFrameBufferHandle hdr_fb_      = render::kGpuInvalidHandle;
    render::GpuFrameBufferHandle bright_fb_   = render::kGpuInvalidHandle;
    render::GpuFrameBufferHandle blur_a_fb_   = render::kGpuInvalidHandle;
    render::GpuFrameBufferHandle blur_b_fb_   = render::kGpuInvalidHandle;

    render::GpuUniformHandle hdr_tex_uniform_        = render::kGpuInvalidHandle;
    render::GpuUniformHandle bloom_tex_uniform_      = render::kGpuInvalidHandle;
    render::GpuUniformHandle blur_tex_uniform_       = render::kGpuInvalidHandle;
    render::GpuUniformHandle bloom_params_uniform_   = render::kGpuInvalidHandle;
    render::GpuUniformHandle blur_params_uniform_    = render::kGpuInvalidHandle;
    render::GpuUniformHandle tonemap_params_uniform_ = render::kGpuInvalidHandle;

private:
    uint32_t pp_w_ = 0, pp_h_ = 0;
    bool pp_enabled_ = false;
    float exposure_ = 1.0f, gamma_ = 2.2f;
    bool bloom_enabled_ = false;
    float bloom_threshold_ = 1.0f, bloom_intensity_ = 1.0f;
    bool ssao_enabled_ = false;
    float ssao_radius_ = 0.5f, ssao_bias_ = 0.025f, ssao_strength_ = 1.0f;
};

} // namespace kernel_engine::render::core
