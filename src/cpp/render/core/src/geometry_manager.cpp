#include "geometry_manager.hpp"
#include "render_context.hpp"
#include "lighting_manager.hpp"
#include "texture_manager.hpp"
#include "gpu_device.hpp"
#include <vector>
#include <cstring>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result GeometryManager::CreateMesh(RenderContext& ctx, const ke_vertex *verts, uint32_t vert_count,
                                        const uint16_t *indices, uint32_t index_count,
                                        ke_mesh_handle *out_handle)
{
    if (!verts || !indices || !out_handle || vert_count == 0 || index_count == 0 || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;

    struct GpuVert {
        float x, y, z;
        float nx, ny, nz;
        float u, v;
        float tx, ty, tz, tw;
    };
    std::vector<GpuVert> expanded(vert_count);
    for (uint32_t i = 0; i < vert_count; i++)
        expanded[i] = {verts[i].x, verts[i].y, verts[i].z,
                       verts[i].nx, verts[i].ny, verts[i].nz,
                       verts[i].u, verts[i].v,
                       verts[i].tx, verts[i].ty, verts[i].tz, verts[i].tw};

    // Note: Layout creation moved to specialized call in BgfxGpuDevice
    // In a real HAL we'd abstract VertexLayout.
    GpuVertexBufferHandle vb = ctx.gpu->CreateVertexBuffer(
        ctx.gpu->Copy(expanded.data(), (uint32_t)(sizeof(GpuVert) * vert_count)), 0 /* Standard Layout ID */);
    GpuIndexBufferHandle ib = ctx.gpu->CreateIndexBuffer(
        ctx.gpu->Copy(indices, sizeof(uint16_t) * index_count));

    if (vb == kGpuInvalidHandle || ib == kGpuInvalidHandle)
        return KE_ERROR_RENDER;

    meshes_.push_back({vb, ib, index_count});
    *out_handle = (ke_mesh_handle)(meshes_.size() - 1);
    return KE_OK;
}

ke_result GeometryManager::DestroyMesh(RenderContext& ctx, ke_mesh_handle handle)
{
    if (handle >= (ke_mesh_handle)meshes_.size() || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    auto &entry = meshes_[handle];
    if (entry.ib != kGpuInvalidHandle) ctx.gpu->DestroyIndexBuffer(entry.ib);
    if (entry.vb != kGpuInvalidHandle) ctx.gpu->DestroyVertexBuffer(entry.vb);
    entry.vb = kGpuInvalidHandle;
    entry.ib = kGpuInvalidHandle;
    return KE_OK;
}

ke_result GeometryManager::SubmitMesh(RenderContext& ctx, 
                                        ke_mesh_handle mesh, 
                                        ke_material_handle material, 
                                        const ke_mat4 *transform,
                                        const LightingManager& lighting,
                                        const TextureManager& textures,
                                        GpuProgramHandle main_program,
                                        GpuProgramHandle depth_program,
                                        GpuProgramHandle prepass_program)
{
    if (!transform || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    if (main_program == kGpuInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    if (mesh >= (ke_mesh_handle)meshes_.size()) return KE_ERROR_INVALID_ARGUMENT;
    
    const auto &entry = meshes_[mesh];
    const auto &mat   = lighting.GetMaterial(material);
    if (entry.vb == kGpuInvalidHandle || !mat.valid) return KE_ERROR_INVALID_ARGUMENT;

    GpuTextureHandle tex_idx   = textures.GetTextureIdx(mat.texture_handle);
    GpuTextureHandle nmap_idx  = textures.GetTextureIdx(mat.normal_map_handle);
    float color[4]     = {mat.r, mat.g, mat.b, mat.a};
    float pbr_params[4]= {mat.metallic, mat.roughness, 0.f, 0.f};

    // ── Depth prepass ─────────────────────────────────────────────────────────
    if (depth_program != kGpuInvalidHandle)
    {
        ctx.gpu->SetTransform(transform->m, 1);
        ctx.gpu->SetVertexBuffer(0, entry.vb);
        ctx.gpu->SetIndexBufferStatic(entry.ib);
        // BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS
        ctx.gpu->SetState(0x0000000000000400ULL | 0x0000000000000010ULL, 0);
        ctx.gpu->Submit(kDepthView, depth_program, 0, false);
    }

    // ── Main scene pass ───────────────────────────────────────────────────────
    ctx.gpu->SetUniform(lighting.color_uniform,         color, 1);
    ctx.gpu->SetUniform(lighting.light_dir_uniform,     lighting.light_dir, 1);
    ctx.gpu->SetUniform(lighting.light_color_uniform,   lighting.light_color, 1);
    ctx.gpu->SetUniform(lighting.ambient_color_uniform, lighting.ambient_color, 1);
    ctx.gpu->SetUniform(lighting.pbr_params_uniform,    pbr_params, 1);
    ctx.gpu->SetUniform(lighting.camera_pos_uniform,    ctx.camera_pos, 1);

    // Texture bindings
    GpuTextureHandle color_tex = (tex_idx != kGpuInvalidHandle) ? tex_idx : textures.GetTextureIdx(0);
    ctx.gpu->SetTexture(0, textures.sampler_uniform, color_tex, 0xFFFFFFFF);

    if (nmap_idx != kGpuInvalidHandle)
    {
        float normal_params[4] = {1.f, 0.f, 0.f, 0.f};
        ctx.gpu->SetUniform(lighting.normal_params_uniform, normal_params, 1);
        ctx.gpu->SetTexture(3, lighting.normal_map_uniform, nmap_idx, 0xFFFFFFFF);
    }

    ctx.gpu->SetVertexBuffer(0, entry.vb);
    ctx.gpu->SetIndexBufferStatic(entry.ib);
    ctx.gpu->SetTransform(transform->m, 1);
    // BGFX_STATE_DEFAULT
    ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000400ULL | 0x0000000000000010ULL | 0x0000000000000020ULL | 0x0000001000000000ULL, 0);
    ctx.gpu->Submit(kSceneView, main_program, 0, false);

    return KE_OK;
}

const MeshEntry& GeometryManager::GetMeshEntry(ke_mesh_handle handle) const
{
    static MeshEntry s_invalid;
    if (handle < meshes_.size()) return meshes_[handle];
    return s_invalid;
}

void GeometryManager::Shutdown()
{
}

} // namespace kernel_engine::render::bgfx
