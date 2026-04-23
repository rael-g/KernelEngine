#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/window/window.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <bgfx/bgfx.h>
#include <string>
#include <memory>

#include "internal_types.hpp"
#include "render_context.hpp"
#include "geometry_manager.hpp"
#include "texture_manager.hpp"
#include "lighting_manager.hpp"
#include "shadow_pipeline.hpp"
#include "post_process_pipeline.hpp"
#include "clustered_forward.hpp"
#include "shader_provider.hpp"
#include "gpu_device.hpp"

namespace kernel_engine::render::bgfx
{

class BgfxLogCallback : public ::bgfx::CallbackI
{
public:
    void SetLogger(struct ke_logger *logger) { logger_ = logger; }

    virtual void fatal(const char *_filePath, uint16_t _line, ::bgfx::Fatal::Enum _code, const char *_str) override;
    virtual void traceVargs(const char *_filePath, uint16_t _line, const char *_format, va_list _argList) override;

    virtual void profilerBegin(const char*, uint32_t, const char*, uint16_t) override {}
    virtual void profilerBeginLiteral(const char*, uint32_t, const char*, uint16_t) override {}
    virtual void profilerEnd() override {}
    virtual uint32_t cacheReadSize(uint64_t) override { return 0; }
    virtual bool cacheRead(uint64_t, void*, uint32_t) override { return false; }
    virtual void cacheWrite(uint64_t, const void*, uint32_t) override {}
    virtual void screenShot(const char*, uint32_t, uint32_t, uint32_t, const void*, uint32_t, bool) override {}
    virtual void captureBegin(uint32_t, uint32_t, uint32_t, ::bgfx::TextureFormat::Enum, bool) override {}
    virtual void captureEnd() override {}
    virtual void captureFrame(const void*, uint32_t) override {}

private:
    struct ke_logger *logger_ = nullptr;
};

class KE_RENDER_API BgfxRenderer
{
public:
    explicit BgfxRenderer(const ke_render_bgfx_params *params);
    ~BgfxRenderer();

    ke_result OnInitialize();
    ke_result OnShutdown();
    ke_result Frame();

    ke_result SetOrthographic(ke_bool enabled);
    ke_result ClearColor(float r, float g, float b, float a);
    ke_result SetViewTransform(const ke_mat4 *view, const ke_mat4 *proj);
    ke_result SetCameraPos(float x, float y, float z);

    // Delegators to managers
    ke_result SetDirectionalLight(const ke_directional_light *light);
    ke_result SetAmbientLight(float r, float g, float b);
    ke_result SetPointLights(const ke_point_light *lights, uint32_t count);
    ke_result SetSpotLights(const ke_spot_light *lights, uint32_t count);
    ke_result SetClusterConfig(const ke_cluster_config *config);
    ke_result SetSsao(ke_bool enabled, float radius, float bias, float strength);
    ke_result SetTonemapping(ke_bool enabled, float exposure, float gamma);
    ke_result SetBloom(ke_bool enabled, float threshold, float intensity);

    ke_render *ToApi();

    // Injects a custom shader provider (useful for testing)
    void SetShaderProvider(ShaderProviderInterface* provider);
    
    // Injects a custom GPU device (useful for testing)
    void SetGpuDevice(GpuDeviceInterface* gpu);

    // Virtual for testing
    virtual ::bgfx::ShaderHandle LoadShader(const char *name);

protected:
    virtual ke_result SetupShader();

private:
    RenderContext ctx_;
    bool own_gpu_device_ = false;
    
    // Modular components (Composition)
    GeometryManager     geometry_;
    TextureManager      textures_;
    LightingManager     lighting_;
    ShadowPipeline      shadows_;
    PostProcessPipeline post_process_;
    ClusteredForward    clustered_;

    uint16_t program_             = kInvalidHandle;
    uint16_t depth_program_       = kInvalidHandle;
    uint16_t cull_program_        = kInvalidHandle;
    uint16_t skybox_program_      = kInvalidHandle;
    uint16_t bright_pass_program_ = kInvalidHandle;
    uint16_t blur_program_        = kInvalidHandle;
    uint16_t tonemap_program_     = kInvalidHandle;
    uint16_t prepass_program_     = kInvalidHandle;
    uint16_t ssao_program_        = kInvalidHandle;
    uint16_t ssao_blur_program_   = kInvalidHandle;
    uint16_t shadow_program_      = kInvalidHandle;

    BgfxLogCallback callback_;
    bool initialized_ = false;
    bool own_shader_provider_ = false;

    ke_render render_api_{};
    struct ke_window* window_ = nullptr;
    std::string shader_path_;
    ::bgfx::RendererType::Enum renderer_type_ = ::bgfx::RendererType::Vulkan;
    bool orthographic_ = true;
};

} // namespace kernel_engine::render::bgfx
