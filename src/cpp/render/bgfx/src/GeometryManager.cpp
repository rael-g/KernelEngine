#include "GeometryManager.hpp"
#include "BgfxRenderer.hpp"
#include "bgfx_interface.hh"
#include <vector>
#include <cstring>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result GeometryManager::CreateMesh(const ke_vertex *verts, uint32_t vert_count,
                                        const uint16_t *indices, uint32_t index_count,
                                        ke_mesh_handle *out_handle)
{
    if (!verts || !indices || !out_handle || vert_count == 0 || index_count == 0) return KE_ERROR_INVALID_ARGUMENT;

    auto* renderer = static_cast<BgfxRenderer*>(this);

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
    entry.vb = renderer->bgfx_->CreateVertexBuffer(
        renderer->bgfx_->Copy(expanded.data(), (uint32_t)(sizeof(GpuVert) * vert_count)), layout).idx;
    entry.ib = renderer->bgfx_->CreateIndexBuffer(
        renderer->bgfx_->Copy(indices, sizeof(uint16_t) * index_count)).idx;
    entry.index_count = index_count;

    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb}) ||
        !::bgfx::isValid(::bgfx::IndexBufferHandle{entry.ib}))
        return KE_ERROR_RENDER;

    meshes_.push_back(entry);
    *out_handle = (ke_mesh_handle)(meshes_.size() - 1);
    return KE_OK;
}

ke_result GeometryManager::DestroyMesh(ke_mesh_handle handle)
{
    if (handle >= (ke_mesh_handle)meshes_.size()) return KE_ERROR_INVALID_ARGUMENT;
    auto* renderer = static_cast<BgfxRenderer*>(this);
    auto &entry = meshes_[handle];
    if (::bgfx::isValid(::bgfx::IndexBufferHandle{entry.ib}))  renderer->bgfx_->Destroy(::bgfx::IndexBufferHandle{entry.ib});
    if (::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb})) renderer->bgfx_->Destroy(::bgfx::VertexBufferHandle{entry.vb});
    entry.vb = kInvalidHandle;
    entry.ib = kInvalidHandle;
    return KE_OK;
}

ke_result GeometryManager::SubmitMesh(ke_mesh_handle mesh, ke_material_handle material, const ke_mat4 *transform)
{
    if (!transform) return KE_ERROR_INVALID_ARGUMENT;
    auto* renderer = static_cast<BgfxRenderer*>(this);
    
    if (!::bgfx::isValid(::bgfx::ProgramHandle{renderer->program_})) return KE_ERROR_NOT_INITIALIZED;
    if (mesh     >= (ke_mesh_handle)meshes_.size())     return KE_ERROR_INVALID_ARGUMENT;
    if (material >= (ke_material_handle)renderer->materials_.size()) return KE_ERROR_INVALID_ARGUMENT;
    
    const auto &entry = meshes_[mesh];
    const auto &mat   = renderer->materials_[material];
    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb}) || !mat.valid) return KE_ERROR_INVALID_ARGUMENT;

    uint32_t tex_idx   = (mat.texture_handle < renderer->textures_.size()) ? mat.texture_handle : 0;
    uint32_t nmap_idx  = (mat.normal_map_handle < renderer->textures_.size()) ? mat.normal_map_handle : 0;
    float color[4]     = {mat.r, mat.g, mat.b, mat.a};
    float pbr_params[4]= {mat.metallic, mat.roughness, 0.f, 0.f};

    // ── Depth prepass (for culling/SSAO) ──────────────────────────────────────
    if (::bgfx::isValid(::bgfx::ProgramHandle{renderer->depth_program_}))
    {
        renderer->bgfx_->SetTransform(transform->m);
        renderer->bgfx_->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
        renderer->bgfx_->SetIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
        renderer->bgfx_->SetState(BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS);
        renderer->bgfx_->Submit(kDepthView, ::bgfx::ProgramHandle{renderer->depth_program_});
    }

    // ── G-buffer prepass (if SSAO enabled) ────────────────────────────────────
    if (renderer->ssao_enabled_ && renderer->prepass_program_ != kInvalidHandle)
    {
        renderer->bgfx_->SetTransform(transform->m);
        renderer->bgfx_->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
        renderer->bgfx_->SetIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
        renderer->bgfx_->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A |
                                   BGFX_STATE_WRITE_Z   | BGFX_STATE_DEPTH_TEST_LESS);
        renderer->bgfx_->Submit(kPrepassView, ::bgfx::ProgramHandle{renderer->prepass_program_});
    }

    // ── Main scene pass ────────────────────────────────────────────────────────
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->color_uniform_},         color);
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->light_dir_uniform_},     renderer->light_dir_);
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->light_color_uniform_},   renderer->light_color_);
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->ambient_color_uniform_}, renderer->ambient_color_);
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->pbr_params_uniform_},    pbr_params);
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->camera_pos_uniform_},    renderer->camera_pos_);

    // Cluster Params
    float clusterParams[4] = {(float)renderer->cluster_config_.grid_x, (float)renderer->cluster_config_.grid_y,
                              (float)renderer->cluster_config_.grid_z, (float)renderer->cluster_config_.max_lights_per_cluster};
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->cluster_params_u_}, clusterParams);

    float clusterParams2[4] = {(float)std::min(renderer->point_lights_.size(), (size_t)64),
                               (float)std::min(renderer->spot_lights_.size(), (size_t)64), renderer->near_z_, renderer->far_z_};
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->cluster_params2_u_}, clusterParams2);

    if (renderer->has_skybox_ && renderer->active_env_tex_ != kInvalidHandle)
    {
        float ibl_params[4] = {1.f, 0.f, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->ibl_params_uniform_}, ibl_params);
        renderer->bgfx_->SetTexture(1, ::bgfx::UniformHandle{renderer->env_map_uniform_}, ::bgfx::TextureHandle{renderer->active_env_tex_});
    }
    else
    {
        float ibl_params[4] = {0.f, 0.f, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->ibl_params_uniform_}, ibl_params);
        uint16_t cube_fb = (renderer->default_cube_tex_ != kInvalidHandle) ? renderer->default_cube_tex_ : renderer->textures_[0].idx;
        renderer->bgfx_->SetTexture(1, ::bgfx::UniformHandle{renderer->env_map_uniform_}, ::bgfx::TextureHandle{cube_fb});
    }

    if (renderer->active_shadow_handle_ != kInvalidShadowHandle)
    {
        float shadow_params[4] = {1.f, 0.f, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->shadow_params_uniform_}, shadow_params);
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->light_vp_uniform_}, renderer->active_light_vp_);
        renderer->bgfx_->SetTexture(2, ::bgfx::UniformHandle{renderer->shadow_map_uniform_},
            ::bgfx::TextureHandle{renderer->shadow_maps_[renderer->active_shadow_handle_].color_tex});
    }
    else
    {
        float shadow_params[4] = {0.f, 0.f, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->shadow_params_uniform_}, shadow_params);
        float identity[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->light_vp_uniform_}, identity);
        renderer->bgfx_->SetTexture(2, ::bgfx::UniformHandle{renderer->shadow_map_uniform_},
            ::bgfx::TextureHandle{renderer->textures_[0].idx});
    }

    if (nmap_idx != 0)
    {
        float normal_params[4] = {1.f, 0.f, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->normal_params_uniform_}, normal_params);
        renderer->bgfx_->SetTexture(3, ::bgfx::UniformHandle{renderer->normal_map_uniform_}, ::bgfx::TextureHandle{renderer->textures_[nmap_idx].idx});
    }
    else
    {
        float normal_params[4] = {0.f, 0.f, 0.f, 0.f};
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->normal_params_uniform_}, normal_params);
        renderer->bgfx_->SetTexture(3, ::bgfx::UniformHandle{renderer->normal_map_uniform_}, ::bgfx::TextureHandle{renderer->textures_[0].idx});
    }

    // SSAO blurred occlusion texture (slot 4) and state uniform
    {
        float ssao_state[4] = {
            renderer->ssao_enabled_ ? 1.f : 0.f,
            (renderer->view_w_ > 0) ? 1.f / (float)renderer->view_w_ : 0.f,
            (renderer->view_h_ > 0) ? 1.f / (float)renderer->view_h_ : 0.f,
            0.f
        };
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->ssao_state_u_}, ssao_state);
        uint16_t ao_tex = (renderer->ssao_enabled_ && renderer->ssao_blur_tex_ != kInvalidHandle)
                              ? renderer->ssao_blur_tex_ : renderer->textures_[0].idx;
        renderer->bgfx_->SetTexture(4, ::bgfx::UniformHandle{renderer->s_ssao_blurred_u_}, ::bgfx::TextureHandle{ao_tex});
    }

    // Point lights uniform array (2 vec4 per light, up to 64)
    {
        static float pl_data[128 * 4] = {};
        uint32_t pCount = (uint32_t)std::min(renderer->point_lights_.size(), (size_t)64);
        for (uint32_t i = 0; i < pCount; ++i)
        {
            const auto &l = renderer->point_lights_[i];
            pl_data[i * 8 + 0] = l.pos_x;
            pl_data[i * 8 + 1] = l.pos_y;
            pl_data[i * 8 + 2] = l.pos_z;
            pl_data[i * 8 + 3] = l.radius;
            pl_data[i * 8 + 4] = l.r * l.intensity;
            pl_data[i * 8 + 5] = l.g * l.intensity;
            pl_data[i * 8 + 6] = l.b * l.intensity;
            pl_data[i * 8 + 7] = 0.f;
        }
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->point_lights_uniform_}, pl_data, 128);
    }

    // Spot lights uniform array (3 vec4 per light, up to 64)
    {
        static float sl_data[192 * 4] = {};
        uint32_t sCount = (uint32_t)std::min(renderer->spot_lights_.size(), (size_t)64);
        for (uint32_t j = 0; j < sCount; ++j)
        {
            const auto &l = renderer->spot_lights_[j];
            sl_data[j * 12 + 0]  = l.pos_x;
            sl_data[j * 12 + 1]  = l.pos_y;
            sl_data[j * 12 + 2]  = l.pos_z;
            sl_data[j * 12 + 3]  = l.range;
            sl_data[j * 12 + 4]  = l.dir_x;
            sl_data[j * 12 + 5]  = l.dir_y;
            sl_data[j * 12 + 6]  = l.dir_z;
            sl_data[j * 12 + 7]  = cosf(l.inner_angle);
            sl_data[j * 12 + 8]  = l.r * l.intensity;
            sl_data[j * 12 + 9]  = l.g * l.intensity;
            sl_data[j * 12 + 10] = l.b * l.intensity;
            sl_data[j * 12 + 11] = cosf(l.outer_angle);
        }
        renderer->bgfx_->SetUniform(::bgfx::UniformHandle{renderer->spot_lights_uniform_}, sl_data, 192);
    }

    renderer->bgfx_->SetTexture(0, ::bgfx::UniformHandle{renderer->sampler_uniform_}, ::bgfx::TextureHandle{renderer->textures_[tex_idx].idx});
    renderer->bgfx_->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
    renderer->bgfx_->SetIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
    renderer->bgfx_->SetTransform(transform->m);
    uint64_t state = BGFX_STATE_DEFAULT & ~BGFX_STATE_CULL_MASK;
    renderer->bgfx_->SetState(state);
    renderer->bgfx_->Submit(kSceneView, ::bgfx::ProgramHandle{renderer->program_});
    return KE_OK;
}

} // namespace kernel_engine::render::bgfx
