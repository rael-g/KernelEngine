#pragma once

#include <cstdint>
#include <kernel_engine/kernel/engine/frame.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/light.h>
#include <kernel_engine/kernel/render/material.h>
#include <kernel_engine/kernel/render/texture.h>
#include <kernel_engine/kernel/render/mesh.h>
#include <kernel_engine/render/bgfx/bgfx_render.hh>
#include <string>
#include <vector>

struct ke_window;

namespace kernel_engine::render::bgfx
{

class BgfxRenderSystem
{
  public:
    explicit BgfxRenderSystem(const ke_render_bgfx_params *params);
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

    // Post-processing
    ke_result SetTonemapping(bool enabled, float exposure, float gamma);
    ke_result SetBloom(bool enabled, float threshold, float intensity);

    // Shadow map operations
    ke_result CreateShadowMap(uint32_t width, uint32_t height, ke_shadow_map_handle *out_handle);
    ke_result DestroyShadowMap(ke_shadow_map_handle handle);
    ke_result BeginShadowPass(ke_shadow_map_handle handle, const ke_mat4 *light_view, const ke_mat4 *light_proj);
    ke_result SubmitMeshShadow(ke_mesh_handle mesh, const ke_mat4 *transform);
    ke_result EndShadowPass();
    ke_result SetShadowMap(ke_shadow_map_handle handle);

    // Material operations
    ke_result CreateMaterial(const ke_material *mat, ke_material_handle *out_handle);
    ke_result DestroyMaterial(ke_material_handle handle);

    // Light operations
    ke_result SetDirectionalLight(const ke_directional_light *light);
    ke_result SetAmbientLight(float r, float g, float b);

    // PBR camera
    ke_result SetCameraPos(float x, float y, float z);

    ke_render *ToApi();

  private:
    ke_result SetupShader();
    ke_result SetupPostProcess();
    ke_result SubmitPostProcess();

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

    struct ShadowMapEntry
    {
        uint16_t color_tex = UINT16_MAX; // R32F — sampled by scene shader
        uint16_t depth_tex = UINT16_MAX; // D16  — depth testing during shadow pass
        uint16_t fb        = UINT16_MAX;
        uint32_t width     = 0;
        uint32_t height    = 0;
        bool valid         = false;
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

    // ── Post-processing ───────────────────────────────────────────────────────
    uint16_t hdr_fb_          = kInvalidHandle; // RGBA16F color + D24 depth
    uint16_t hdr_color_tex_   = kInvalidHandle; // RGBA16F color attachment (for sampling)
    uint16_t bright_fb_       = kInvalidHandle; // bright-pass result (half-res RGBA16F)
    uint16_t blur_a_fb_       = kInvalidHandle; // horizontal blur result (half-res RGBA16F)
    uint16_t blur_b_fb_       = kInvalidHandle; // vertical blur result = final bloom

    uint16_t fullscreen_vb_   = kInvalidHandle;
    uint16_t fullscreen_ib_   = kInvalidHandle;

    uint16_t bright_pass_program_ = kInvalidHandle;
    uint16_t blur_program_        = kInvalidHandle;
    uint16_t tonemap_program_     = kInvalidHandle;

    uint16_t hdr_tex_uniform_      = kInvalidHandle; // s_hdrTex
    uint16_t bloom_tex_uniform_    = kInvalidHandle; // s_bloomTex
    uint16_t blur_tex_uniform_     = kInvalidHandle; // s_blurTex
    uint16_t bloom_params_uniform_ = kInvalidHandle; // u_bloomParams
    uint16_t blur_params_uniform_  = kInvalidHandle; // u_blurParams
    uint16_t tonemap_params_uniform_ = kInvalidHandle; // u_tonemapParams

    bool  pp_enabled_      = false;
    float exposure_        = 1.0f;
    float gamma_           = 2.2f;
    bool  bloom_enabled_   = false;
    float bloom_threshold_ = 1.0f;
    float bloom_intensity_ = 0.5f;

    int pp_w_ = 0, pp_h_ = 0; // half-resolution for bloom passes

    // ── Shadow maps ───────────────────────────────────────────────────────────
    uint16_t shadow_program_        = kInvalidHandle;
    uint16_t shadow_map_uniform_    = kInvalidHandle; // s_shadowMap sampler
    uint16_t light_vp_uniform_      = kInvalidHandle; // u_lightVP mat4
    uint16_t shadow_params_uniform_ = kInvalidHandle; // u_shadowParams vec4

    std::vector<ShadowMapEntry> shadow_maps_;

    // Per-frame shadow state (reset each Frame())
    static constexpr uint32_t kInvalidShadowHandle = UINT32_MAX;
    uint32_t active_shadow_handle_ = kInvalidShadowHandle;
    float    active_light_vp_[16]{};
};

} // namespace kernel_engine::render::bgfx
