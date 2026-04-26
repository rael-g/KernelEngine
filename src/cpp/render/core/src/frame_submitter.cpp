#include "../include/frame_submitter.hpp"
#include "render_context.hpp"
#include "../include/geometry_manager.hpp"
#include "../include/lighting_manager.hpp"
#include "../include/texture_manager.hpp"
#include "../include/shadow_pipeline.hpp"
#include "gpu_device.hpp"
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/engine/frame_packet.h>

namespace kernel_engine::render::bgfx
{

ke_result FrameSubmitter::Submit(RenderContext& ctx,
                                 const struct ke_frame_packet& packet,
                                 const GeometryManager& geometry,
                                 LightingManager& lighting,
                                 TextureManager& textures,
                                 ShadowPipeline& shadows,
                                 GpuProgramHandle main_program,
                                 GpuProgramHandle shadow_program,
                                 GpuProgramHandle skybox_program,
                                 GpuProgramHandle /*prepass_program*/)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;

    // ── 1. Apply lighting from packet ────────────────────────────────────────
    if (packet.has_dir_light)
        lighting.SetDirectionalLight(&packet.dir_light);

    if (packet.point_light_count > 0)
        lighting.StorePointLights(packet.point_lights, packet.point_light_count);

    if (packet.spot_light_count > 0)
        lighting.StoreSpotLights(packet.spot_lights, packet.spot_light_count);

    ctx.gpu->SetUniform(lighting.light_dir_uniform,     lighting.light_dir,     1);
    ctx.gpu->SetUniform(lighting.light_color_uniform,   lighting.light_color,   1);
    ctx.gpu->SetUniform(lighting.ambient_color_uniform, lighting.ambient_color, 1);

    float camera_pos[4] = {packet.camera.pos_x, packet.camera.pos_y, packet.camera.pos_z, 1.0f};
    ctx.gpu->SetUniform(lighting.camera_pos_uniform, camera_pos, 1);

    // ── 2. Shadow Pass ───────────────────────────────────────────────────────
    if (packet.shadow.map_handle != 0xFFFFFFFFu)
    {
        shadows.BeginShadowPass(ctx, packet.shadow.map_handle,
                                &packet.shadow.light_view, &packet.shadow.light_proj);

        for (uint32_t i = 0; i < packet.shadow_draw_count; ++i)
        {
            const auto& cmd = packet.shadow_draw_commands[i];
            shadows.SubmitMeshShadow(ctx, geometry, shadow_program,
                                     static_cast<ke_mesh_handle>(cmd.mesh_handle), &cmd.transform);
        }

        shadows.EndShadowPass(ctx);
    }

    // ── 3. Scene View Transform ──────────────────────────────────────────────
    ctx.gpu->SetViewTransform(1 /*SCENE*/, packet.camera.view.m, packet.camera.proj.m);

    // ── 4. Skybox Pass ───────────────────────────────────────────────────────
    if (packet.has_skybox && skybox_program != kGpuInvalidHandle)
    {
        textures.SubmitSkybox(ctx, static_cast<ke_texture_handle>(packet.skybox_handle),
                              skybox_program,
                              geometry.skybox_vb, geometry.skybox_ib,
                              textures.skybox_sampler_uniform, textures.skybox_tint_uniform);
    }

    // ── 5. Main Scene Pass ───────────────────────────────────────────────────
    for (uint32_t i = 0; i < packet.draw_count; ++i)
    {
        const auto& cmd   = packet.draw_commands[i];
        const auto& entry = geometry.GetMeshEntry(static_cast<ke_mesh_handle>(cmd.mesh_handle));
        const auto& mat   = lighting.GetMaterial(static_cast<ke_material_handle>(cmd.material_handle));

        if (entry.vb == kGpuInvalidHandle || !mat.valid) continue;

        float color[4] = {mat.r, mat.g, mat.b, mat.a};
        float pbr[4]   = {mat.metallic, mat.roughness, 0.0f, 0.0f};
        ctx.gpu->SetUniform(lighting.color_uniform,      color, 1);
        ctx.gpu->SetUniform(lighting.pbr_params_uniform, pbr,   1);

        GpuTextureHandle tex = textures.GetTextureIdx(static_cast<ke_texture_handle>(mat.texture_handle));
        if (tex == kGpuInvalidHandle) tex = textures.default_2d_tex;
        GpuTextureHandle shadow_tex = shadows.GetActiveShadowTex();
        if (shadow_tex == kGpuInvalidHandle) shadow_tex = textures.default_2d_tex;
        GpuTextureHandle nmap_tex = textures.GetTextureIdx(static_cast<ke_texture_handle>(mat.normal_map_handle));
        float normal_params[4] = {nmap_tex != kGpuInvalidHandle ? 1.0f : 0.0f, 0.f, 0.f, 0.f};
        if (nmap_tex == kGpuInvalidHandle) nmap_tex = textures.default_2d_tex;
        ctx.gpu->SetUniform(lighting.normal_params_uniform, normal_params, 1);
        ctx.gpu->SetTexture(0, textures.sampler_uniform,      tex,                        0xFFFFFFFF);
        ctx.gpu->SetTexture(1, lighting.env_map_uniform,      textures.default_cube_tex,  0xFFFFFFFF);
        ctx.gpu->SetTexture(2, shadows.shadow_map_uniform,    shadow_tex,                 0xFFFFFFFF);
        ctx.gpu->SetTexture(3, lighting.normal_map_uniform,   nmap_tex,                   0xFFFFFFFF);
        ctx.gpu->SetTexture(4, textures.ssao_blurred_uniform, textures.default_2d_tex,    0xFFFFFFFF);

        ctx.gpu->SetTransform(cmd.transform.m, 1);
        ctx.gpu->SetVertexBuffer(0, entry.vb);
        ctx.gpu->SetIndexBufferStatic(entry.ib);
        // WRITE_RGBA | WRITE_Z | DEPTH_TEST_LESS | MSAA — no cull (meshes are two-sided)
        ctx.gpu->SetState(UINT64_C(0x010000400000001F), 0);
        ctx.gpu->Submit(1 /*SCENE*/, main_program, 0, false);
    }

    return KE_OK;
}

} // namespace kernel_engine::render::bgfx
