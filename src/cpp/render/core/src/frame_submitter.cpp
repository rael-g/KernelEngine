#include "frame_submitter.hpp"
#include "render_context.hpp"
#include "geometry_manager.hpp"
#include "lighting_manager.hpp"
#include "texture_manager.hpp"
#include "shadow_pipeline.hpp"
#include "post_process_pipeline.hpp"
#include "clustered_forward.hpp"
#include "gpu_device.hpp"
#include "view_ids.hpp"
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include <kernel_engine/threading/threading.h>


namespace kernel_engine::render::core
{

ke_result FrameSubmitter::Submit(RenderContext& ctx,
                                 const struct ke_frame_packet& packet,
                                 const GeometryManager& geometry,
                                 LightingManager& lighting,
                                 TextureManager& textures,
                                 ShadowPipeline& shadows,
                                 PostProcessPipeline& post_process,
                                 GpuProgramHandle main_program,
                                 GpuProgramHandle shadow_program,
                                 GpuProgramHandle skybox_program,
                                 GpuProgramHandle /*prepass_program*/,
                                 GpuProgramHandle ui_quad_program,
                                 uint16_t backbuffer_width,
                                 uint16_t backbuffer_height,
                                 ClusteredForward* clustered)
{
    ke_thread_assert_current("ke.render");
    if (!ctx.gpu) return KE_ERROR_RENDER;

    // Global state + lighting upload extracted in Phase 6.1 to
    // CoreRenderer::ExecuteLightsUploadPass (graph node "lights.upload"). DAG
    // forces it to run before this pass so all scene-shader uniforms +
    // lighting buffers are populated by the time we reach the draw loop.
    (void)post_process;
    (void)shadows;

    // Clustered light cull (compute, view 0 by default). Stays here until
    // Phase 6.2 extracts it into a dedicated compute graph pass. Must run
    // before the scene draws — bgfx orders view 0 (cull) before view 1 (scene)
    // automatically so the compute-write → fragment-read barrier is honoured.
    if (clustered) clustered->RunCull(ctx, lighting);

    // ── 3. Scene View Transform ──────────────────────────────────────────────
    ctx.gpu->SetViewTransform(Id(ViewId::Scene), packet.camera.view.m, packet.camera.proj.m);

    // Skybox draw was here — extracted into CoreRenderer::ExecuteSkyboxPass as a separate
    // graph node. The IBL env-tex resolution stays in the scene pass because the main
    // lighting shader samples it whether or not the skybox geometry is drawn.
    GpuTextureHandle env_tex = textures.default_cube_tex;
    if (packet.has_skybox)
    {
        GpuTextureHandle sky = textures.GetTextureIdx(packet.skybox_handle);
        if (sky != kGpuInvalidHandle) env_tex = sky;
    }

    // ── 5. Main Scene Pass ───────────────────────────────────────────────────
    for (uint32_t i = 0; i < packet.draw_count; ++i)
    {
        const auto& cmd   = packet.draw_commands[i];
        const auto& entry = geometry.GetMeshEntry(cmd.mesh_handle);
        const auto& mat   = lighting.GetMaterial(cmd.material_handle);

        if (entry.vb == kGpuInvalidHandle || !mat.valid) continue;

        float color[4] = {mat.r, mat.g, mat.b, mat.a};
        float pbr[4]   = {mat.metallic, mat.roughness, 0.0f, 0.0f};
        ctx.gpu->SetUniform(lighting.color_uniform,      color, 1);
        ctx.gpu->SetUniform(lighting.pbr_params_uniform, pbr,   1);

        GpuTextureHandle tex = textures.GetTextureIdx(mat.texture_handle);
        if (tex == kGpuInvalidHandle) tex = textures.default_2d_tex;
        GpuTextureHandle shadow_tex = shadows.GetActiveShadowTex();
        if (shadow_tex == kGpuInvalidHandle) shadow_tex = textures.default_2d_tex;
        GpuTextureHandle nmap_tex = ke_texture_is_valid(mat.normal_map_handle)
            ? textures.GetTextureIdx(mat.normal_map_handle)
            : kGpuInvalidHandle;
        float normal_params[4] = {nmap_tex != kGpuInvalidHandle ? 1.0f : 0.0f, 0.f, 0.f, 0.f};
        if (nmap_tex == kGpuInvalidHandle) nmap_tex = textures.default_2d_tex;
        ctx.gpu->SetUniform(lighting.normal_params_uniform, normal_params, 1);
        ctx.gpu->SetTexture(0, textures.sampler_uniform,      tex,                        0xFFFFFFFF);
        ctx.gpu->SetTexture(1, lighting.env_map_uniform,      env_tex,                    0xFFFFFFFF);
        ctx.gpu->SetTexture(2, shadows.shadow_map_uniform,    shadow_tex,                 0xFFFFFFFF);
        ctx.gpu->SetTexture(3, lighting.normal_map_uniform,   nmap_tex,                   0xFFFFFFFF);
        ctx.gpu->SetTexture(4, textures.ssao_blurred_uniform, textures.default_2d_tex,    0xFFFFFFFF);

        ctx.gpu->SetTransform(cmd.transform.m, 1);
        ctx.gpu->SetVertexBuffer(0, entry.vb);
        ctx.gpu->SetIndexBufferStatic(entry.ib);
        if (clustered) clustered->BindForSceneRead(ctx);
        // no cull (meshes are two-sided)
        ctx.gpu->SetState(GpuStateFlags::WriteRgba | GpuStateFlags::WriteZ | GpuStateFlags::DepthTestLess | GpuStateFlags::Msaa, 0);
        ctx.gpu->Submit(Id(ViewId::Scene), main_program, 0, false);
    }

    // UI overlay extracted in Step F — CoreRenderer::ExecuteUiPass via graph
    // node "ui.overlay". ui_quad_program + backbuffer_width/height parameters
    // are no longer consumed here; kept on the signature pending a wider
    // FrameSubmitter signature trim (will land alongside Phase 3 cleanup).
    (void)ui_quad_program;
    (void)backbuffer_width;
    (void)backbuffer_height;
    return KE_OK;
}

} // namespace kernel_engine::render::core
