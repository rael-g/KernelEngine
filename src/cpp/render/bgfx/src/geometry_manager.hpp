#pragma once

#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/mesh.h>
#include <kernel_engine/kernel/render/material.h>
#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "internal_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class LightingManager;
class TextureManager;

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
    ke_result CreateMesh(RenderContext& ctx, const ke_vertex *verts, uint32_t vert_count,
                         const uint16_t *indices, uint32_t index_count,
                         ke_mesh_handle *out_handle);
    ke_result DestroyMesh(RenderContext& ctx, ke_mesh_handle handle);
    
    ke_result SubmitMesh(RenderContext& ctx, 
                         ke_mesh_handle mesh, 
                         ke_material_handle material, 
                         const ke_mat4 *transform,
                         const LightingManager& lighting,
                         const TextureManager& textures,
                         uint16_t main_program,
                         uint16_t depth_program,
                         uint16_t prepass_program);

    void Shutdown();

    const MeshEntry& GetMeshEntry(ke_mesh_handle handle) const;

    // Internal primitives
    uint16_t skybox_vb     = kInvalidHandle;
    uint16_t skybox_ib     = kInvalidHandle;
    uint16_t fullscreen_vb = kInvalidHandle;
    uint16_t fullscreen_ib = kInvalidHandle;

private:
    std::vector<MeshEntry> meshes_;
};

} // namespace kernel_engine::render::bgfx
