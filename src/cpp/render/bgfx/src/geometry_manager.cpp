#include "geometry_manager.hpp"
#include "render_context.hpp"
#include "lighting_manager.hpp"
#include "texture_manager.hpp"
#include "gpu_device.hpp"
#include <bgfx/bgfx.h>
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

    ::bgfx::VertexLayout layout;
    layout.begin()
        .add(::bgfx::Attrib::Position,  3, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::Normal,    3, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::TexCoord0, 2, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::Tangent,   4, ::bgfx::AttribType::Float)
        .end();

    MeshEntry entry;
    entry.vb = ctx.gpu->CreateVertexBuffer(
        ctx.gpu->Copy(expanded.data(), (uint32_t)(sizeof(GpuVert) * vert_count)), layout).idx;
    entry.ib = ctx.gpu->CreateIndexBuffer(
        ctx.gpu->Copy(indices, sizeof(uint16_t) * index_count)).idx;
    entry.index_count = index_count;

    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb}) ||
        !::bgfx::isValid(::bgfx::IndexBufferHandle{entry.ib}))
        return KE_ERROR_RENDER;

    meshes_.push_back(entry);
    *out_handle = (ke_mesh_handle)(meshes_.size() - 1);
    return KE_OK;
}

ke_result GeometryManager::DestroyMesh(RenderContext& ctx, ke_mesh_handle handle)
{
    if (handle >= (ke_mesh_handle)meshes_.size() || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    auto &entry = meshes_[handle];
    if (::bgfx::isValid(::bgfx::IndexBufferHandle{entry.ib}))  ctx.gpu->Destroy(::bgfx::IndexBufferHandle{entry.ib});
    if (::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb})) ctx.gpu->Destroy(::bgfx::VertexBufferHandle{entry.vb});
    entry.vb = kInvalidHandle;
    entry.ib = kInvalidHandle;
    return KE_OK;
}

ke_result GeometryManager::SubmitMesh(RenderContext& ctx, 
                                        ke_mesh_handle mesh, 
                                        ke_material_handle material, 
                                        const ke_mat4 *transform,
                                        const LightingManager& lighting,
                                        const TextureManager& textures,
                                        uint16_t main_program,
                                        uint16_t depth_program,
                                        uint16_t prepass_program)
{
    if (!transform || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    if (!::bgfx::isValid(::bgfx::ProgramHandle{main_program})) return KE_ERROR_NOT_INITIALIZED;
    if (mesh >= (ke_mesh_handle)meshes_.size()) return KE_ERROR_INVALID_ARGUMENT;
    
    const auto &entry = meshes_[mesh];
    const auto &mat   = lighting.GetMaterial(material);
    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb}) || !mat.valid) return KE_ERROR_INVALID_ARGUMENT;

    uint16_t tex_idx   = textures.GetTextureIdx(mat.texture_handle);
    uint16_t nmap_idx  = textures.GetTextureIdx(mat.normal_map_handle);
    float color[4]     = {mat.r, mat.g, mat.b, mat.a};
    float pbr_params[4]= {mat.metallic, mat.roughness, 0.f, 0.f};

    // ── Depth prepass ─────────────────────────────────────────────────────────
    if (::bgfx::isValid(::bgfx::ProgramHandle{depth_program}))
    {
        ctx.gpu->SetTransform(transform->m, 1);
        ctx.gpu->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
        ctx.gpu->SetIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
        ctx.gpu->SetState(BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS, 0);
        ctx.gpu->Submit(kDepthView, ::bgfx::ProgramHandle{depth_program}, 0, false);
    }

    // ── Main scene pass ───────────────────────────────────────────────────────
    ctx.gpu->SetUniform(::bgfx::UniformHandle{lighting.color_uniform},         color, 1);
    ctx.gpu->SetUniform(::bgfx::UniformHandle{lighting.light_dir_uniform},     lighting.light_dir, 1);
    ctx.gpu->SetUniform(::bgfx::UniformHandle{lighting.light_color_uniform},   lighting.light_color, 1);
    ctx.gpu->SetUniform(::bgfx::UniformHandle{lighting.ambient_color_uniform}, lighting.ambient_color, 1);
    ctx.gpu->SetUniform(::bgfx::UniformHandle{lighting.pbr_params_uniform},    pbr_params, 1);
    ctx.gpu->SetUniform(::bgfx::UniformHandle{lighting.camera_pos_uniform},    ctx.camera_pos, 1);

    // Texture bindings
    uint16_t color_tex = (tex_idx != kInvalidHandle) ? tex_idx : textures.GetTextureIdx(0);
    ctx.gpu->SetTexture(0, ::bgfx::UniformHandle{textures.sampler_uniform}, ::bgfx::TextureHandle{color_tex}, 0xFFFFFFFF);

    if (nmap_idx != kInvalidHandle)
    {
        float normal_params[4] = {1.f, 0.f, 0.f, 0.f};
        ctx.gpu->SetUniform(::bgfx::UniformHandle{lighting.normal_params_uniform}, normal_params, 1);
        ctx.gpu->SetTexture(3, ::bgfx::UniformHandle{lighting.normal_map_uniform}, ::bgfx::TextureHandle{nmap_idx}, 0xFFFFFFFF);
    }

    ctx.gpu->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
    ctx.gpu->SetIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
    ctx.gpu->SetTransform(transform->m, 1);
    ctx.gpu->SetState(BGFX_STATE_DEFAULT, 0);
    ctx.gpu->Submit(kSceneView, ::bgfx::ProgramHandle{main_program}, 0, false);

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
