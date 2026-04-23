#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class LightingManager;
class TextureManager;

struct MeshEntry
{
    GpuVertexBufferHandle vb = kGpuInvalidHandle;
    GpuIndexBufferHandle ib  = kGpuInvalidHandle;
    uint32_t index_count     = 0;
};

/**
 * @brief Manages GPU geometry resources using the HAL.
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
                         GpuProgramHandle main_program,
                         GpuProgramHandle depth_program,
                         GpuProgramHandle prepass_program);

    void Shutdown();

    const MeshEntry& GetMeshEntry(ke_mesh_handle handle) const;

    GpuVertexBufferHandle skybox_vb      = kGpuInvalidHandle;
    GpuIndexBufferHandle  skybox_ib      = kGpuInvalidHandle;
    GpuVertexBufferHandle fullscreen_vb  = kGpuInvalidHandle;
    GpuIndexBufferHandle  fullscreen_ib  = kGpuInvalidHandle;

private:
    std::vector<MeshEntry> meshes_;
};

} // namespace kernel_engine::render::bgfx
