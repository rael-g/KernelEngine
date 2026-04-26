#include "geometry_manager.hpp"
#include "lighting_manager.hpp"
#include "texture_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <kernel_engine/kernel/engine/frame_packet.h>
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
    
    GpuVertexBufferHandle vb = ctx.gpu->CreateVertexBuffer(
        ctx.gpu->Copy(expanded.data(), (uint32_t)(sizeof(GpuVert) * vert_count)), kVertexLayoutStandard);
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

ke_result GeometryManager::RecordDraw(struct ke_frame_packet& packet, 
                                      ke_mesh_handle mesh, 
                                      ke_material_handle material, 
                                      const ke_mat4 *transform)
{
    if (!transform) return KE_ERROR_INVALID_ARGUMENT;
    if (packet.draw_count >= packet.draw_capacity) return KE_ERROR_OUT_OF_MEMORY;

    ke_draw_command& cmd = packet.draw_commands[packet.draw_count++];
    cmd.mesh_handle = mesh;
    cmd.material_handle = material;
    cmd.transform = *transform;

    return KE_OK;
}

const MeshEntry& GeometryManager::GetMeshEntry(ke_mesh_handle handle) const
{
    static MeshEntry s_invalid;
    if (handle < (ke_mesh_handle)meshes_.size()) return meshes_[handle];
    return s_invalid;
}

ke_result GeometryManager::SubmitMesh(RenderContext& ctx, ke_mesh_handle mesh, ke_material_handle material,
                                       const ke_mat4 *transform, LightingManager& lighting,
                                       TextureManager& textures, GpuProgramHandle program,
                                       GpuProgramHandle, GpuProgramHandle)
{
    if (!ctx.gpu || !transform) return KE_ERROR_INVALID_ARGUMENT;

    const auto& entry = GetMeshEntry(mesh);
    if (entry.vb == kGpuInvalidHandle) return KE_ERROR_INVALID_ARGUMENT;

    const auto& mat = lighting.GetMaterial(material);
    if (!mat.valid) return KE_ERROR_INVALID_ARGUMENT;

    float color[4] = {mat.r, mat.g, mat.b, mat.a};
    float pbr[4]   = {mat.metallic, mat.roughness, 0.0f, 0.0f};
    ctx.gpu->SetUniform(lighting.color_uniform, color, 1);
    ctx.gpu->SetUniform(lighting.pbr_params_uniform, pbr, 1);

    GpuTextureHandle tex = textures.GetTextureIdx(mat.texture_handle);
    if (tex == kGpuInvalidHandle) tex = textures.default_cube_tex;
    ctx.gpu->SetTexture(0, textures.sampler_uniform, tex, 0xFFFFFFFF);

    ctx.gpu->SetTransform(transform->m, 1);
    ctx.gpu->SetVertexBuffer(0, entry.vb);
    ctx.gpu->SetIndexBufferStatic(entry.ib);
    ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000400ULL | 0x0000000000000010ULL | 0x0000000000000020ULL | 0x0000001000000000ULL, 0);
    ctx.gpu->Submit(1, program, 0, false);

    return KE_OK;
}

void GeometryManager::Shutdown()
{
    meshes_.clear();
}

} // namespace kernel_engine::render::bgfx
