#include "../include/frame_submitter.hpp"
#include "render_context.hpp"
#include "../include/geometry_manager.hpp"
#include "../include/lighting_manager.hpp"
#include "../include/texture_manager.hpp"
#include "gpu_device.hpp"
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/engine/frame_packet.h>

namespace kernel_engine::render::bgfx
{

ke_result FrameSubmitter::Submit(RenderContext& ctx, 
                                 const struct ke_frame_packet& packet,
                                 const GeometryManager& geometry,
                                 const LightingManager& lighting,
                                 const TextureManager& textures,
                                 GpuProgramHandle main_program,
                                 GpuProgramHandle shadow_program,
                                 GpuProgramHandle prepass_program)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;

    // 1. Update Global Uniforms from Packet
    ctx.gpu->SetViewTransform(1 /*SceneView*/, packet.camera.view.m, packet.camera.proj.m);
    
    float camera_pos[4] = {packet.camera.pos_x, packet.camera.pos_y, packet.camera.pos_z, 1.0f};
    ctx.gpu->SetUniform(lighting.camera_pos_uniform, camera_pos, 1);

    // 2. Process Draw Commands
    for (uint32_t i = 0; i < packet.draw_count; ++i)
    {
        const auto& cmd = packet.draw_commands[i];
        const auto& entry = geometry.GetMeshEntry(cmd.mesh_handle);
        const auto& mat = lighting.GetMaterial(cmd.material_handle);
        
        if (entry.vb != kGpuInvalidHandle && mat.valid)
        {
            // Material Setup (Agnostic)
            float color[4] = {mat.r, mat.g, mat.b, mat.a};
            float pbr[4]   = {mat.metallic, mat.roughness, 0.0f, 0.0f};
            
            ctx.gpu->SetUniform(lighting.color_uniform, color, 1);
            ctx.gpu->SetUniform(lighting.pbr_params_uniform, pbr, 1);
            
            // Texture Bindings
            GpuTextureHandle tex = textures.GetTextureIdx(mat.texture_handle);
            if (tex == kGpuInvalidHandle) tex = textures.default_cube_tex;
            
            // Note: sampler_uniform is in TextureManager
            ctx.gpu->SetTexture(0, textures.sampler_uniform, tex, 0xFFFFFFFF);

            ctx.gpu->SetTransform(cmd.transform.m, 1);
            ctx.gpu->SetVertexBuffer(0, entry.vb);
            ctx.gpu->SetIndexBufferStatic(entry.ib);
            
            // BGFX_STATE_DEFAULT
            ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000400ULL | 0x0000000000000010ULL | 0x0000000000000020ULL | 0x0000001000000000ULL, 0);
            ctx.gpu->Submit(1 /*SceneView*/, main_program, 0, false);
        }
    }

    return KE_OK;
}

} // namespace kernel_engine::render::bgfx
