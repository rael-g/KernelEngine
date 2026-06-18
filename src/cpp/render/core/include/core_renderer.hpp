#pragma once

#include <kernel_engine/render/render.h>
#include <kernel_engine/render/frame_packet.h>
#include "../src/geometry_manager.hpp"
#include "../src/texture_manager.hpp"
#include "../src/lighting_manager.hpp"
#include "../src/shadow_pipeline.hpp"
#include "../src/post_process_pipeline.hpp"
#include "../src/clustered_forward.hpp"
#include "../src/shader_provider.hpp"
#include <gpu_device.hpp>
#include <gpu_types.hpp>
#include "../src/render_context.hpp"
#include <string>

namespace kernel_engine::render::core
{

/**
 * @brief High-level renderer service implementing the agnostic core logic.
 */
class CoreRenderer
{
public:
    explicit CoreRenderer(const render::GpuRendererParams& params); 
    virtual ~CoreRenderer();

    ke_result OnInitialize();
    ke_result OnShutdown();
    
    // Legacy frame (immediate)
    ke_result Frame();
    
    // NEW: Multithreaded frame submission
    ke_result SubmitPacket(const struct ke_frame_packet* packet);

    ke_result ClearColor(float r, float g, float b, float a);
    ke_result SetOrthographic(bool enabled);
    ke_result SetViewTransform(const ke_mat4 *view, const ke_mat4 *proj);
    ke_result SetCameraPos(float x, float y, float z);
    
    ke_result SetDirectionalLight(const ke_directional_light *light);
    ke_result SetAmbientLight(float r, float g, float b);
    ke_result SetPointLights(const ke_point_light *lights, uint32_t count);
    ke_result SetSpotLights(const ke_spot_light *lights, uint32_t count);

    ke_result SetClusterConfig(const ke_cluster_config *config);
    ke_result SetSsao(bool enabled, float radius, float bias, float strength);
    ke_result SetTonemapping(bool enabled, float exposure, float gamma);
    ke_result SetBloom(bool enabled, float threshold, float intensity);

    const char* GetLastFatalError();

    ke_render *ToApi();

    /// Owner-handle destroy: tears down the renderer and frees its allocation.
    static void DestroyApi(ke_render *self);

    /// @brief Accessor used by the render-graph executor to reach the shared
    /// renderer state (GPU device, logger, allocator) without re-passing
    /// them on every call. Not stable public API — internal to render-core.
    RenderContext& GetContext() { return ctx_; }

    /// @brief Reports the current backbuffer size in pixels. Read from the
    /// owning window, so it tracks resizes without manual notification.
    void GetBackbufferSize(uint32_t* out_w, uint32_t* out_h) const;

    /// @brief Creates a render graph bound to this renderer. Wired through the
    /// @c create_render_graph slot on @c ke_render so callers go through the
    /// generic kernel contract.
    ke_render_graph_handle CreateRenderGraph(ke_allocator* allocator);

    /// @brief Returns the renderer's active graph (the one executed on
    /// @c SubmitPacket). Used by external/managed code to plug new passes
    /// into the running chain. Returns a borrow — ownership stays with the renderer.
    struct ke_render_graph* GetRenderGraph() { return graph_; }

    void SetShaderProvider(ShaderProviderInterface* provider);
    void SetGpuDevice(render::GpuDevice* gpu);

    virtual render::GpuShaderHandle LoadShader(const char *name);

protected:
    virtual ke_result SetupShader();

private:
    /// @brief Builds the render graph used by SubmitPacket. Phase 3 Step A
    /// installs a single "scene.legacy_monolithic" pass that wraps the original
    /// FrameSubmitter chain — orchestration goes through the graph immediately,
    /// internal pipeline code stays untouched. Steps B-H split that pass into
    /// per-stage callbacks.
    ke_result SetupRenderGraph();

    /// @brief Runs the directional shadow depth pass — split out of the
    /// monolithic pass in Phase 3 Step B. Skips silently when the packet
    /// carries no valid shadow map handle.
    ke_result ExecuteShadowPass(const struct ke_frame_packet* packet);

    /// @brief Renders the skybox cube around the camera (Phase 3 Step C).
    /// Skips silently when the packet carries no skybox or the skybox program
    /// failed to load. Runs after the main scene pass — depth-test LEQUAL fills
    /// only pixels the scene left at the far plane.
    ke_result ExecuteSkyboxPass(const struct ke_frame_packet* packet);

    /// @brief SSAO compose pass (Phase 3 Step D). No-op until
    /// PostProcessPipeline::SetupSsao stops being a stub (OBS.4) — extracted
    /// here so the future fix lands inside the graph instead of the legacy chain.
    ke_result ExecuteSsaoPass(const struct ke_frame_packet* packet);

    /// @brief HDR post-fx chain (bright-pass + 2-tap blur + ACES tonemap) plus
    /// the scene-FB redirect when tonemap is disabled (Phase 3 Step E). The
    /// chain is bundled because @c PostProcessPipeline::SubmitPostProcess
    /// already runs all three views in one call; gating them with one toggle
    /// matches the legacy semantics 1:1.
    ke_result ExecutePostFxPass(const struct ke_frame_packet* packet);

    /// @brief UI overlay pass (Phase 3 Step F). Renders the packet's
    /// @c ui_draw_commands as 2D textured quads in backbuffer pixel space.
    /// Runs after every other pass so the overlay composites on top.
    ke_result ExecuteUiPass(const struct ke_frame_packet* packet);

    /// @brief Lights + scene-shader uniform upload pass (Phase 6.1). Pure
    /// CPU pack + SetUniform calls — no GPU draws or dispatches. Runs first
    /// in the chain so subsequent passes (cluster cull, scene draws) see
    /// fresh light/camera/ambient/ibl uniforms.
    ke_result ExecuteLightsUploadPass(const struct ke_frame_packet* packet);

    /// @brief Clustered light culling compute dispatch (Phase 6.2). Reads
    /// the stored light arrays, packs them into the cluster cull's storage
    /// buffers, and dispatches the CS that bins lights into screen-space
    /// clusters. Runs between @c lights.upload and the main scene pass.
    ke_result ExecuteClusterCullPass(const struct ke_frame_packet* packet);

    /// @brief Main opaque scene pass (Phase 6.3). Sets the scene-view
    /// transform and submits one draw per @c ke_draw_command, binding the
    /// material colors, textures, shadow map, env cubemap, normal map, and
    /// (via @c ClusteredForward::BindForSceneRead) the cluster buffers. The
    /// last block of the legacy chain — its extraction completes F.RC2 and
    /// retires @c FrameSubmitter + @c SubmitPacketLegacy.
    ke_result ExecuteSceneOpaquePass(const struct ke_frame_packet* packet);

    RenderContext ctx_;
    bool own_gpu_device_ = false;
    bool own_shader_provider_ = false;
    bool initialized_ = false;
    
    GeometryManager     geometry_;
    TextureManager      textures_;
    LightingManager     lighting_;
    ShadowPipeline      shadows_;
    PostProcessPipeline post_process_;
    ClusteredForward    clustered_;

    render::GpuProgramHandle program_             = render::kGpuInvalidHandle;
    render::GpuProgramHandle shadow_program_      = render::kGpuInvalidHandle;
    render::GpuProgramHandle skybox_program_      = render::kGpuInvalidHandle;
    render::GpuProgramHandle bright_pass_program_ = render::kGpuInvalidHandle;
    render::GpuProgramHandle blur_program_        = render::kGpuInvalidHandle;
    render::GpuProgramHandle tonemap_program_     = render::kGpuInvalidHandle;
    render::GpuProgramHandle prepass_program_     = render::kGpuInvalidHandle;
    render::GpuProgramHandle ssao_program_        = render::kGpuInvalidHandle;
    render::GpuProgramHandle ssao_blur_program_   = render::kGpuInvalidHandle;
    render::GpuProgramHandle depth_program_       = render::kGpuInvalidHandle;
    render::GpuProgramHandle cull_program_        = render::kGpuInvalidHandle;
    render::GpuProgramHandle ui_quad_program_     = render::kGpuInvalidHandle;

    ke_render render_api_{};
    ke_render_graph_handle  graph_owner_{};     // owner handle; built in OnInitialize.
    struct ke_render_graph* graph_ = nullptr;   // borrow of graph_owner_.ref, for internal calls.
    struct ke_window* window_ = nullptr;
    std::string shader_path_;
    uint32_t renderer_type_ = 0;
    bool vsync_ = true;
    bool orthographic_ = true;
};

} // namespace kernel_engine::render::core
