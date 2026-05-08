#include "geometry_manager.hpp"
#include <render_logging.hpp>
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <kernel_engine/kernel/engine/frame_packet.h>
#include <vector>
#include <cstring>

namespace kernel_engine::render::bgfx
{

ke_result GeometryManager::CreateMesh(RenderContext& ctx, const ke_vertex *verts, uint32_t vert_count,
                                        const uint16_t *indices, uint32_t index_count,
                                        ke_mesh_handle *out_handle)
{
    if (!verts || !indices || !out_handle || vert_count == 0 || index_count == 0 || !ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "CreateMesh", "Invalid arguments or GPU not set");

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
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "CreateMesh", "GPU resource creation failed");

    meshes_.push_back({vb, ib, index_count});
    *out_handle = {(uint32_t)(meshes_.size() - 1)};
    return KE_OK;
}

ke_result GeometryManager::DestroyMesh(RenderContext& ctx, ke_mesh_handle handle)
{
    if (handle.idx >= (uint32_t)meshes_.size() || !ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "DestroyMesh", "Invalid mesh handle or GPU not set");
    auto &entry = meshes_[handle.idx];
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
    if (handle.idx < (uint32_t)meshes_.size()) return meshes_[handle.idx];
    return s_invalid;
}

void GeometryManager::Shutdown()
{
    meshes_.clear();
}

} // namespace kernel_engine::render::bgfx
