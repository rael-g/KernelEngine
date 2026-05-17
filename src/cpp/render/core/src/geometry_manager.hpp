#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include "render_export.h"
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

#include <kernel_engine/render/core/render_core_export.h>

namespace kernel_engine::render::core
{

struct RenderContext;

struct MeshEntry
{
    render::GpuVertexBufferHandle vb = render::kGpuInvalidHandle;
    render::GpuIndexBufferHandle ib  = render::kGpuInvalidHandle;
    uint32_t index_count     = 0;
};

/**
 * @brief Manages GPU geometry resources using the HAL.
 */
class KE_RENDER_CORE_API GeometryManager
{
public:
    ke_result CreateMesh(RenderContext& ctx, const ke_vertex *verts, uint32_t vert_count,
                         const uint16_t *indices, uint32_t index_count,
                         ke_mesh_handle *out_handle);
    ke_result DestroyMesh(RenderContext& ctx, ke_mesh_handle handle);

    // Records a draw command instead of submitting immediately
    ke_result RecordDraw(struct ke_frame_packet& packet,
                         ke_mesh_handle mesh,
                         ke_material_handle material,
                         const ke_mat4 *transform);

    void Shutdown();

    const MeshEntry& GetMeshEntry(ke_mesh_handle handle) const;

    render::GpuVertexBufferHandle skybox_vb      = render::kGpuInvalidHandle;
    render::GpuIndexBufferHandle  skybox_ib      = render::kGpuInvalidHandle;
    render::GpuVertexBufferHandle fullscreen_vb  = render::kGpuInvalidHandle;
    render::GpuIndexBufferHandle  fullscreen_ib  = render::kGpuInvalidHandle;

private:
    std::vector<MeshEntry> meshes_;
};

} // namespace kernel_engine::render::core
