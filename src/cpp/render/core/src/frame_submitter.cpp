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

    // ── 0. Global State ──────────────────────────────────────────────────────
    uint32_t clear_color = (uint32_t(packet.clear_color[0] * 255.0F) << 24) |
                           (uint32_t(packet.clear_color[1] * 255.0F) << 16) |
                           (uint32_t(packet.clear_color[2] * 255.0F) << 8)  |
                           (uint32_t(packet.clear_color[3] * 255.0F));
    ctx.gpu->SetViewClear(Id(ViewId::Scene), GpuClearFlags::Color | GpuClearFlags::Depth, clear_color, 1.0f, 0);

    lighting.SetAmbientLight(packet.ambient_light[0], packet.ambient_light[1], packet.ambient_light[2]);

    if (ke_shadow_map_is_valid(packet.active_shadow_map))
        shadows.SetShadowMap(ctx, packet.active_shadow_map);

    // ── Post-Processing & Pipeline ────────────────────────────────────────
    post_process.SetSsao(ctx, packet.ssao_enabled, packet.ssao_radius, packet.ssao_bias, packet.ssao_strength);
    post_process.SetTonemapping(ctx, packet.tonemapping_enabled, packet.exposure, packet.gamma);
    post_process.SetBloom(ctx, packet.bloom_enabled, packet.bloom_threshold, packet.bloom_intensity);

    // ── 1. Apply lighting from packet ────────────────────────────────────────
    if (packet.has_dir_light)
        lighting.SetDirectionalLight(&packet.dir_light);

    // Always store (even count 0) so last frame's lights don't persist.
    lighting.StorePointLights(packet.point_lights, packet.point_light_count);
    lighting.StoreSpotLights(packet.spot_lights, packet.spot_light_count);

    ctx.gpu->SetUniform(lighting.light_dir_uniform,     lighting.light_dir,     1);
    ctx.gpu->SetUniform(lighting.light_color_uniform,   lighting.light_color,   1);
    ctx.gpu->SetUniform(lighting.ambient_color_uniform, lighting.ambient_color, 1);

    float camera_pos[4] = {packet.camera.pos_x, packet.camera.pos_y, packet.camera.pos_z, 1.0f};
    ctx.gpu->SetUniform(lighting.camera_pos_uniform, camera_pos, 1);

    float ibl_params[4] = {packet.has_skybox ? 1.0f : 0.0f, 0, 0, 0};
    ctx.gpu->SetUniform(lighting.ibl_params_uniform, ibl_params, 1);

    // Pack + upload point/spot lights into u_pointLights/u_spotLights + u_lightCounts (forward path).
    lighting.UploadLights(ctx);

    // Light cull (compute, view 0) — submitted BEFORE the scene draws (view 1) so bgfx orders the
    // compute-write → fragment-read barrier correctly. Lights were just stored above, so the cull
    // sees this frame's positions (no 1-frame lag).
    if (clustered) clustered->RunCull(ctx, lighting);

    // Shadow pass was here — extracted into CoreRenderer::ExecuteShadowPass and
    // registered as its own render-graph node. The legacy_remaining pass now
    // declares a read on "shadow_map" so the DAG runs the shadow pass first.

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
