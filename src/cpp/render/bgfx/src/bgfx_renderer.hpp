#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "geometry_manager.hpp"
#include "texture_manager.hpp"
#include "lighting_manager.hpp"
#include "shadow_pipeline.hpp"
#include "post_process_pipeline.hpp"
#include "clustered_forward.hpp"
#include "shader_provider.hpp"
#include "gpu_device.hpp"
#include "gpu_types.hpp"
#include "render_context.hpp"
#include <string>

namespace kernel_engine::render::bgfx
{

/**
 * @brief High-level renderer service implementing the bgfx backend.
 * 100% Backend agnostic in its logic.
 */
class KE_RENDER_API BgfxRenderer
{
public:
    explicit BgfxRenderer(const ke_render_bgfx_params *params);
    virtual ~BgfxRenderer();

    // ── Service API ──────────────────────────────────────────────────────────
    ke_result OnInitialize();
    ke_result OnShutdown();
    ke_result Frame();

    ke_result ClearColor(float r, float g, float b, float a);
    ke_result SetOrthographic(ke_bool enabled);
    ke_result SetViewTransform(const ke_mat4 *view, const ke_mat4 *proj);
    ke_result SetCameraPos(float x, float y, float z);
    
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
    virtual GpuShaderHandle LoadShader(const char *name);

protected:
    virtual ke_result SetupShader();

private:
    RenderContext ctx_;
    bool own_gpu_device_ = false;
    bool own_shader_provider_ = false;
    bool initialized_ = false;
    
    // Modular components (Composition)
    GeometryManager     geometry_;
    TextureManager      textures_;
    LightingManager     lighting_;
    ShadowPipeline      shadows_;
    PostProcessPipeline post_process_;
    ClusteredForward    clustered_;

    // Global resources
    GpuProgramHandle program_             = kGpuInvalidHandle;
    GpuProgramHandle shadow_program_      = kGpuInvalidHandle;
    GpuProgramHandle skybox_program_      = kGpuInvalidHandle;
    GpuProgramHandle bright_pass_program_ = kGpuInvalidHandle;
    GpuProgramHandle blur_program_        = kGpuInvalidHandle;
    GpuProgramHandle tonemap_program_     = kGpuInvalidHandle;
    GpuProgramHandle prepass_program_     = kGpuInvalidHandle;
    GpuProgramHandle ssao_program_        = kGpuInvalidHandle;
    GpuProgramHandle ssao_blur_program_   = kGpuInvalidHandle;
    GpuProgramHandle depth_program_       = kGpuInvalidHandle;
    GpuProgramHandle cull_program_        = kGpuInvalidHandle;

    ke_render render_api_{};
    struct ke_window* window_ = nullptr;
    std::string shader_path_;
    uint32_t renderer_type_ = 0; 
    bool orthographic_ = true;
};

} // namespace kernel_engine::render::bgfx
