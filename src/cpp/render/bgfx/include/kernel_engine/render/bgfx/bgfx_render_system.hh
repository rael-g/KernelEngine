#pragma once

#include <cstdint>
#include <kernel_engine/kernel/common/descriptor.h>
#include <kernel_engine/kernel/engine/frame.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/light.h>
#include <kernel_engine/kernel/render/material.h>
#include <kernel_engine/kernel/render/texture.h>
#include <kernel_engine/kernel/render/mesh.h>
#include <kernel_engine/render/bgfx/render_plugin.hh>
#include <string>
#include <vector>

struct ke_window;

namespace kernel_engine::render::bgfx
{

class BgfxRenderSystem
{
  public:
    explicit BgfxRenderSystem(const ke_render_bgfx_descriptor *desc);
    ~BgfxRenderSystem();

    ke_result OnInitialize();
    ke_result OnShutdown();

    // Render operations
    ke_result Frame();
    ke_result SetOrthographic(bool enabled);
    ke_result ClearColor(float r, float g, float b, float a);
    ke_result SetViewTransform(const ke_mat4 *view, const ke_mat4 *proj);

    // Mesh resource operations
    ke_result CreateMesh(const ke_vertex *verts, uint32_t vert_count,
                         const uint16_t *indices, uint32_t index_count,
                         ke_mesh_handle *out_handle);
    ke_result DestroyMesh(ke_mesh_handle handle);
    ke_result SubmitMesh(ke_mesh_handle mesh, ke_material_handle material, const ke_mat4 *transform);

    // Texture operations
    ke_result CreateTextureRgba(uint32_t width, uint32_t height, const uint8_t *pixels,
                                ke_texture_handle *out_handle);
    ke_result DestroyTexture(ke_texture_handle handle);

    // Cubemap / skybox operations
    ke_result CreateCubemapRgba(uint32_t size, const uint8_t *data, ke_texture_handle *out_handle);
    ke_result SubmitSkybox(ke_texture_handle cubemap_handle);

    // Material operations
    ke_result CreateMaterial(const ke_material_descriptor *desc, ke_material_handle *out_handle);
    ke_result DestroyMaterial(ke_material_handle handle);

    // Light operations
    ke_result SetDirectionalLight(const ke_directional_light *light);
    ke_result SetAmbientLight(float r, float g, float b);

    // PBR camera
    ke_result SetCameraPos(float x, float y, float z);

    ke_render *ToApi();

  private:
    ke_result SetupShader();

    struct TextureEntry
    {
        uint16_t idx  = UINT16_MAX;
        bool valid    = false;
    };

    struct MeshEntry
    {
        uint16_t vb          = UINT16_MAX;
        uint16_t ib          = UINT16_MAX;
        uint32_t index_count = 0;
    };

    struct MaterialEntry
    {
        float r = 1.f, g = 1.f, b = 1.f, a = 1.f;
        uint32_t texture_handle = 0; // index into textures_
        float metallic  = 0.f;
        float roughness = 0.5f;
        bool valid = false;
    };

    ke_render render_api_{};

    struct ke_window* window_ = nullptr;
    ke_allocator *allocator_ = nullptr;
    ke_logger *logger_ = nullptr;
    std::string shader_path_;
    bool orthographic_ = true;

    static constexpr uint16_t kInvalidHandle = UINT16_MAX;

    // ── Scene program (PBR) ───────────────────────────────────────────────────
    uint16_t program_         = kInvalidHandle;
    uint16_t sampler_uniform_ = kInvalidHandle;
    uint16_t color_uniform_   = kInvalidHandle;

    std::vector<TextureEntry>  textures_;  // handle 0 = built-in white
    std::vector<MeshEntry>     meshes_;    // handle 0 = built-in unit quad
    std::vector<MaterialEntry> materials_; // handle 0 = built-in white material

    uint16_t light_dir_uniform_     = kInvalidHandle;
    uint16_t light_color_uniform_   = kInvalidHandle;
    uint16_t ambient_color_uniform_ = kInvalidHandle;
    uint16_t pbr_params_uniform_    = kInvalidHandle;
    uint16_t camera_pos_uniform_    = kInvalidHandle;
    uint16_t ibl_params_uniform_    = kInvalidHandle;
    uint16_t env_map_uniform_       = kInvalidHandle; // s_envMap for IBL

    float light_dir_[4]     = {0.f,  1.f, 0.f, 0.f};
    float light_color_[4]   = {0.f,  0.f, 0.f, 0.f};
    float ambient_color_[4] = {0.1f, 0.1f, 0.1f, 0.f};
    float camera_pos_[4]    = {0.f,  0.f, 0.f, 0.f};

    // ── Skybox program ────────────────────────────────────────────────────────
    uint16_t skybox_program_         = kInvalidHandle;
    uint16_t skybox_vb_              = kInvalidHandle;
    uint16_t skybox_ib_              = kInvalidHandle;
    uint16_t skybox_sampler_uniform_ = kInvalidHandle; // s_skybox
    uint16_t skybox_tint_uniform_    = kInvalidHandle; // u_skyboxTint

    // Stored per-frame for skybox rotation-only view
    float last_view_[16]{};
    float last_proj_[16]{};
    int   view_w_ = 0, view_h_ = 0;

    // IBL state (set by SubmitSkybox, read by SubmitMesh within the same frame)
    bool     has_skybox_       = false;
    uint16_t active_env_tex_   = kInvalidHandle;
};

} // namespace kernel_engine::render::bgfx
