#pragma once

#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/mesh.h>
#include <kernel_engine/kernel/render/material.h>
#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "InternalTypes.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct MeshEntry
{
    uint16_t vb          = kInvalidHandle;
    uint16_t ib          = kInvalidHandle;
    uint32_t index_count = 0;
};

/**
 * @brief Manages geometry resources (Vertex Buffers, Index Buffers).
 */
class KE_RENDER_API GeometryManager
{
public:
    ke_result CreateMesh(const ke_vertex *verts, uint32_t vert_count,
                         const uint16_t *indices, uint32_t index_count,
                         ke_mesh_handle *out_handle);
    ke_result DestroyMesh(ke_mesh_handle handle);
    ke_result SubmitMesh(ke_mesh_handle mesh, ke_material_handle material, const ke_mat4 *transform);

protected:
    std::vector<MeshEntry> meshes_;
    uint16_t skybox_vb_     = kInvalidHandle;
    uint16_t skybox_ib_     = kInvalidHandle;
    uint16_t fullscreen_vb_ = kInvalidHandle;
    uint16_t fullscreen_ib_ = kInvalidHandle;
};

} // namespace kernel_engine::render::bgfx
