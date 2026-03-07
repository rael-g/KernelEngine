#include <kernel_engine/render/bgfx/bgfx_render_system.hh>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/window/window.h>
#include <new>
#include <bgfx/bgfx.h>
#include <bgfx/platform.h>
#include <fstream>
#include <string>
#include <vector>
#include <cstring>
#include <cmath>

namespace kernel_engine::render::bgfx
{

BgfxRenderSystem::BgfxRenderSystem(const ke_render_bgfx_params *params)
    : allocator_(params->allocator), logger_(params->logger), window_(params->window),
      shader_path_((params->shader_path != nullptr) ? params->shader_path : "")
{
    render_api_.handle = this;
    render_api_.on_initialize = [](ke_render *self) {
        return static_cast<BgfxRenderSystem *>(self->handle)->OnInitialize();
    };
    render_api_.on_shutdown = [](ke_render *self) {
        return static_cast<BgfxRenderSystem *>(self->handle)->OnShutdown();
    };
    render_api_.destroy = [](ke_render *self) {
        auto *sys = static_cast<BgfxRenderSystem *>(self->handle);
        auto *alloc = sys->allocator_;
        sys->~BgfxRenderSystem();
        alloc->free(alloc, sys);
    };
    render_api_.frame = [](ke_render *self) {
        return static_cast<BgfxRenderSystem *>(self->handle)->Frame();
    };
    render_api_.clear_color = [](ke_render *self, float r, float g, float b, float a) {
        return static_cast<BgfxRenderSystem *>(self->handle)->ClearColor(r, g, b, a);
    };
    render_api_.set_orthographic = [](ke_render *self, bool enabled) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetOrthographic(enabled);
    };
    render_api_.set_view_transform = [](ke_render *self, const ke_mat4 *view, const ke_mat4 *proj) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetViewTransform(view, proj);
    };
    render_api_.create_texture_rgba = [](ke_render *self, uint32_t w, uint32_t h,
                                          const uint8_t *px, ke_texture_handle *out) {
        return static_cast<BgfxRenderSystem *>(self->handle)->CreateTextureRgba(w, h, px, out);
    };
    render_api_.destroy_texture = [](ke_render *self, ke_texture_handle handle) {
        return static_cast<BgfxRenderSystem *>(self->handle)->DestroyTexture(handle);
    };
    render_api_.create_mesh = [](ke_render *self, const ke_vertex *verts, uint32_t vc,
                                  const uint16_t *idx, uint32_t ic, ke_mesh_handle *out) {
        return static_cast<BgfxRenderSystem *>(self->handle)->CreateMesh(verts, vc, idx, ic, out);
    };
    render_api_.destroy_mesh = [](ke_render *self, ke_mesh_handle handle) {
        return static_cast<BgfxRenderSystem *>(self->handle)->DestroyMesh(handle);
    };
    render_api_.create_material = [](ke_render *self, const ke_material *mat,
                                      ke_material_handle *out) {
        return static_cast<BgfxRenderSystem *>(self->handle)->CreateMaterial(mat, out);
    };
    render_api_.destroy_material = [](ke_render *self, ke_material_handle handle) {
        return static_cast<BgfxRenderSystem *>(self->handle)->DestroyMaterial(handle);
    };
    render_api_.submit_mesh = [](ke_render *self, ke_mesh_handle mesh, ke_material_handle mat,
                                  const ke_mat4 *transform) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SubmitMesh(mesh, mat, transform);
    };
    render_api_.set_directional_light = [](ke_render *self, const ke_directional_light *light) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetDirectionalLight(light);
    };
    render_api_.set_ambient_light = [](ke_render *self, float r, float g, float b) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetAmbientLight(r, g, b);
    };
    render_api_.set_camera_pos = [](ke_render *self, float x, float y, float z) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetCameraPos(x, y, z);
    };
    render_api_.create_cubemap_rgba = [](ke_render *self, uint32_t size,
                                          const uint8_t *data, ke_texture_handle *out) {
        return static_cast<BgfxRenderSystem *>(self->handle)->CreateCubemapRgba(size, data, out);
    };
    render_api_.submit_skybox = [](ke_render *self, ke_texture_handle handle) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SubmitSkybox(handle);
    };
    render_api_.create_shadow_map = [](ke_render *self, uint32_t w, uint32_t h,
                                        ke_shadow_map_handle *out) {
        return static_cast<BgfxRenderSystem *>(self->handle)->CreateShadowMap(w, h, out);
    };
    render_api_.destroy_shadow_map = [](ke_render *self, ke_shadow_map_handle handle) {
        return static_cast<BgfxRenderSystem *>(self->handle)->DestroyShadowMap(handle);
    };
    render_api_.begin_shadow_pass = [](ke_render *self, ke_shadow_map_handle handle,
                                        const ke_mat4 *lv, const ke_mat4 *lp) {
        return static_cast<BgfxRenderSystem *>(self->handle)->BeginShadowPass(handle, lv, lp);
    };
    render_api_.submit_mesh_shadow = [](ke_render *self, ke_mesh_handle mesh,
                                         const ke_mat4 *transform) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SubmitMeshShadow(mesh, transform);
    };
    render_api_.end_shadow_pass = [](ke_render *self) {
        return static_cast<BgfxRenderSystem *>(self->handle)->EndShadowPass();
    };
    render_api_.set_shadow_map = [](ke_render *self, ke_shadow_map_handle handle) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetShadowMap(handle);
    };
    render_api_.set_tonemapping = [](ke_render *self, bool enabled, float exposure, float gamma) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetTonemapping(enabled, exposure, gamma);
    };
    render_api_.set_bloom = [](ke_render *self, bool enabled, float threshold, float intensity) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetBloom(enabled, threshold, intensity);
    };
    render_api_.set_point_lights = [](ke_render *self, const ke_point_light *lights, uint32_t count) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetPointLights(lights, count);
    };
    render_api_.set_spot_lights = [](ke_render *self, const ke_spot_light *lights, uint32_t count) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetSpotLights(lights, count);
    };
    render_api_.set_ssao = [](ke_render *self, bool enabled, float radius, float bias, float strength) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetSsao(enabled, radius, bias, strength);
    };
    render_api_.set_cluster_config = [](ke_render *self, const ke_cluster_config *config) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetClusterConfig(config);
    };
}

BgfxRenderSystem::~BgfxRenderSystem() {}
ke_render *BgfxRenderSystem::ToApi() { return &render_api_; }

ke_result BgfxRenderSystem::OnInitialize()
{
    if (!window_) return KE_ERROR_NOT_INITIALIZED;
    void *nwh = window_->get_native_handle(window_);
    if (!nwh) return KE_ERROR_WINDOW;

    ::bgfx::Init init;
    init.type = ::bgfx::RendererType::Vulkan;
    init.platformData.nwh = nwh;

    int w, h;
    window_->get_size(window_, &w, &h);
    init.resolution.width  = (uint32_t)w;
    init.resolution.height = (uint32_t)h;
    init.resolution.reset  = BGFX_RESET_VSYNC;

    if (!::bgfx::init(init))
    {
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "bgfx", "bgfx::init() failed"};
        if (logger_) logger_->log(logger_, &ev);
        return KE_ERROR_RENDER;
    }

    {
        ke_log_event ev = {KE_LOG_LEVEL_INFO, "bgfx", "bgfx initialized"};
        if (logger_) logger_->log(logger_, &ev);
    }

    view_w_ = w;
    view_h_ = h;

    // View 0: shadow depth pass — FB and transform set dynamically by BeginShadowPass.
    // View 1: Light Cull (Compute)
    // View 2: Depth Prepass (for Cluster Culling)
    // Views 3-5: SSAO prepass, SSAO raw, SSAO blur.
    // View 6: main scene forward pass.
    ::bgfx::setViewClear(kDepthView, BGFX_CLEAR_DEPTH, 0, 1.0f, 0);
    ::bgfx::setViewRect(kDepthView, 0, 0, (uint16_t)w, (uint16_t)h);

    ::bgfx::setViewClear(kSceneView, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 0x303030ff, 1.0f, 0);
    ::bgfx::setViewRect(kSceneView, 0, 0, (uint16_t)w, (uint16_t)h);
    // View 7: skybox pass — no clear, renders only where scene left depth=1.
    ::bgfx::setViewClear(kSkyboxView, BGFX_CLEAR_NONE);
    ::bgfx::setViewRect(kSkyboxView, 0, 0, (uint16_t)w, (uint16_t)h);

    ke_result res = SetupShader();
    if (res != KE_OK) return res;
    res = SetupPostProcess();
    if (res != KE_OK) return res;
    res = SetupSsao();
    if (res != KE_OK) return res;
    return SetupClustered();
}

ke_result BgfxRenderSystem::SetupShader()
{
    auto load_shader = [&](const char *name) -> ::bgfx::ShaderHandle {
        std::string path = shader_path_ + "/" + name + ".bin";
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open()) return ::bgfx::ShaderHandle{::bgfx::kInvalidHandle};
        auto size = (uint32_t)file.tellg();
        file.seekg(0);
        const ::bgfx::Memory *mem = ::bgfx::alloc(size + 1);
        file.read(reinterpret_cast<char *>(mem->data), size);
        mem->data[size] = '\0';
        return ::bgfx::createShader(mem);
    };

    ::bgfx::ShaderHandle vs = load_shader("vs_basic");
    ::bgfx::ShaderHandle fs = load_shader("fs_basic");
    if (!::bgfx::isValid(vs) || !::bgfx::isValid(fs))
    {
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "bgfx", "Failed to load scene shaders"};
        if (logger_) logger_->log(logger_, &ev);
        return KE_ERROR_RENDER;
    }
    ::bgfx::ProgramHandle prog = ::bgfx::createProgram(vs, fs, true);
    if (!::bgfx::isValid(prog)) return KE_ERROR_RENDER;
    program_ = prog.idx;

    ::bgfx::ShaderHandle shd_vs = load_shader("vs_shadow");
    ::bgfx::ShaderHandle shd_fs = load_shader("fs_shadow");
    if (::bgfx::isValid(shd_vs) && ::bgfx::isValid(shd_fs))
    {
        ::bgfx::ProgramHandle shd_prog = ::bgfx::createProgram(shd_vs, shd_fs, true);
        if (::bgfx::isValid(shd_prog))
            shadow_program_ = shd_prog.idx;
    }
    else
    {
        if (::bgfx::isValid(shd_vs)) ::bgfx::destroy(shd_vs);
        if (::bgfx::isValid(shd_fs)) ::bgfx::destroy(shd_fs);
        ke_log_event ev = {KE_LOG_LEVEL_WARNING, "bgfx", "Shadow shaders not found — shadows disabled"};
        if (logger_) logger_->log(logger_, &ev);
    }

    ::bgfx::ShaderHandle sky_vs = load_shader("vs_skybox");
    ::bgfx::ShaderHandle sky_fs = load_shader("fs_skybox");
    if (::bgfx::isValid(sky_vs) && ::bgfx::isValid(sky_fs))
    {
        ::bgfx::ProgramHandle sky_prog = ::bgfx::createProgram(sky_vs, sky_fs, true);
        if (::bgfx::isValid(sky_prog))
            skybox_program_ = sky_prog.idx;
    }
    else
    {
        if (::bgfx::isValid(sky_vs)) ::bgfx::destroy(sky_vs);
        if (::bgfx::isValid(sky_fs)) ::bgfx::destroy(sky_fs);
        ke_log_event ev = {KE_LOG_LEVEL_WARNING, "bgfx", "Skybox shaders not found — skybox disabled"};
        if (logger_) logger_->log(logger_, &ev);
    }

    // Normal=(0,0,1) Tangent=(1,0,0,1) → Bitangent=cross(N,T)*1=(0,1,0)
    static const ke_vertex kVerts[4] = {
        {-0.5f, -0.5f, 0.0f,  0.0f, 0.0f, 1.0f,  0.0f, 0.0f,  1.0f, 0.0f, 0.0f, 1.0f},
        { 0.5f, -0.5f, 0.0f,  0.0f, 0.0f, 1.0f,  1.0f, 0.0f,  1.0f, 0.0f, 0.0f, 1.0f},
        { 0.5f,  0.5f, 0.0f,  0.0f, 0.0f, 1.0f,  1.0f, 1.0f,  1.0f, 0.0f, 0.0f, 1.0f},
        {-0.5f,  0.5f, 0.0f,  0.0f, 0.0f, 1.0f,  0.0f, 1.0f,  1.0f, 0.0f, 0.0f, 1.0f},
    };
    static const uint16_t kIndices[6] = {0, 1, 2, 0, 2, 3};
    ke_mesh_handle quad_handle;
    if (CreateMesh(kVerts, 4, kIndices, 6, &quad_handle) != KE_OK) return KE_ERROR_RENDER;

    struct SkyVert { float x, y, z; };
    static const SkyVert kSkyVerts[8] = {
        {-1,-1,-1}, { 1,-1,-1}, { 1, 1,-1}, {-1, 1,-1},
        {-1,-1, 1}, { 1,-1, 1}, { 1, 1, 1}, {-1, 1, 1},
    };
    static const uint16_t kSkyIdx[36] = {
        0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,4,7, 0,7,3, 1,2,6, 1,6,5, 0,1,5, 0,5,4, 2,3,7, 2,7,6,
    };
    ::bgfx::VertexLayout skyLayout;
    skyLayout.begin()
        .add(::bgfx::Attrib::Position, 3, ::bgfx::AttribType::Float)
        .end();
    skybox_vb_ = ::bgfx::createVertexBuffer(
        ::bgfx::copy(kSkyVerts, sizeof(kSkyVerts)), skyLayout).idx;
    skybox_ib_ = ::bgfx::createIndexBuffer(
        ::bgfx::copy(kSkyIdx, sizeof(kSkyIdx))).idx;

    uint32_t white = 0xffffffff;
    ke_texture_handle white_handle;
    if (CreateTextureRgba(1, 1, reinterpret_cast<const uint8_t *>(&white), &white_handle) != KE_OK)
        return KE_ERROR_RENDER;

    sampler_uniform_       = ::bgfx::createUniform("s_texColor",     ::bgfx::UniformType::Sampler).idx;
    env_map_uniform_       = ::bgfx::createUniform("s_envMap",       ::bgfx::UniformType::Sampler).idx;
    color_uniform_         = ::bgfx::createUniform("u_color",         ::bgfx::UniformType::Vec4).idx;
    light_dir_uniform_     = ::bgfx::createUniform("u_lightDir",      ::bgfx::UniformType::Vec4).idx;
    light_color_uniform_   = ::bgfx::createUniform("u_lightColor",    ::bgfx::UniformType::Vec4).idx;
    ambient_color_uniform_ = ::bgfx::createUniform("u_ambientColor",  ::bgfx::UniformType::Vec4).idx;
    pbr_params_uniform_    = ::bgfx::createUniform("u_pbrParams",     ::bgfx::UniformType::Vec4).idx;
    camera_pos_uniform_    = ::bgfx::createUniform("u_cameraPos",     ::bgfx::UniformType::Vec4).idx;
    ibl_params_uniform_    = ::bgfx::createUniform("u_iblParams",     ::bgfx::UniformType::Vec4).idx;
    normal_map_uniform_    = ::bgfx::createUniform("s_normalMap",     ::bgfx::UniformType::Sampler).idx;
    normal_params_uniform_ = ::bgfx::createUniform("u_normalParams",  ::bgfx::UniformType::Vec4).idx;
    skybox_sampler_uniform_ = ::bgfx::createUniform("s_skybox",       ::bgfx::UniformType::Sampler).idx;
    skybox_tint_uniform_    = ::bgfx::createUniform("u_skyboxTint",   ::bgfx::UniformType::Vec4).idx;
    shadow_map_uniform_     = ::bgfx::createUniform("s_shadowMap",    ::bgfx::UniformType::Sampler).idx;
    light_vp_uniform_       = ::bgfx::createUniform("u_lightVP",      ::bgfx::UniformType::Mat4).idx;
    shadow_params_uniform_  = ::bgfx::createUniform("u_shadowParams", ::bgfx::UniformType::Vec4).idx;
    light_counts_uniform_   = ::bgfx::createUniform("u_lightCounts",  ::bgfx::UniformType::Vec4).idx;
    point_lights_uniform_   = ::bgfx::createUniform("u_pointLights",  ::bgfx::UniformType::Vec4, 128).idx;
    spot_lights_uniform_    = ::bgfx::createUniform("u_spotLights",   ::bgfx::UniformType::Vec4, 192).idx;

    ke_material white_mat = {1.f, 1.f, 1.f, 1.f};
    ke_material_handle mat_handle;
    if (CreateMaterial(&white_mat, &mat_handle) != KE_OK) return KE_ERROR_RENDER;

    ke_log_event ev = {KE_LOG_LEVEL_INFO, "bgfx", "Shaders and resources ready"};
    if (logger_) logger_->log(logger_, &ev);
    return KE_OK;
}

ke_result BgfxRenderSystem::OnShutdown()
{
    for (auto &t : textures_)
        if (::bgfx::isValid(::bgfx::TextureHandle{t.idx})) ::bgfx::destroy(::bgfx::TextureHandle{t.idx});
    textures_.clear();

    for (auto &entry : meshes_)
    {
        if (::bgfx::isValid(::bgfx::IndexBufferHandle{entry.ib}))  ::bgfx::destroy(::bgfx::IndexBufferHandle{entry.ib});
        if (::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb})) ::bgfx::destroy(::bgfx::VertexBufferHandle{entry.vb});
    }
    meshes_.clear();

    if (::bgfx::isValid(::bgfx::VertexBufferHandle{skybox_vb_})) ::bgfx::destroy(::bgfx::VertexBufferHandle{skybox_vb_});
    if (::bgfx::isValid(::bgfx::IndexBufferHandle{skybox_ib_}))  ::bgfx::destroy(::bgfx::IndexBufferHandle{skybox_ib_});

    auto destroy_uniform = [](uint16_t u) {
        if (::bgfx::isValid(::bgfx::UniformHandle{u})) ::bgfx::destroy(::bgfx::UniformHandle{u});
    };
    auto destroy_fb = [](uint16_t h) {
        if (::bgfx::isValid(::bgfx::FrameBufferHandle{h})) ::bgfx::destroy(::bgfx::FrameBufferHandle{h});
    };
    auto destroy_tex = [](uint16_t h) {
        if (::bgfx::isValid(::bgfx::TextureHandle{h})) ::bgfx::destroy(::bgfx::TextureHandle{h});
    };

    // Post-process uniforms
    destroy_uniform(tonemap_params_uniform_);
    destroy_uniform(blur_params_uniform_);
    destroy_uniform(bloom_params_uniform_);
    destroy_uniform(blur_tex_uniform_);
    destroy_uniform(bloom_tex_uniform_);
    destroy_uniform(hdr_tex_uniform_);

    // SSAO resources
    destroy_fb(gbuf_fb_);
    destroy_fb(ssao_raw_fb_);
    destroy_fb(ssao_blur_fb_);
    destroy_tex(ssao_noise_tex_);
    destroy_uniform(ssao_state_u_);
    destroy_uniform(ssao_blur_params_u_);
    destroy_uniform(ssao_proj_info_u_);
    destroy_uniform(ssao_params_u_);
    destroy_uniform(ssao_kernel_u_);
    destroy_uniform(s_ssao_blurred_u_);
    destroy_uniform(s_ssao_input_u_);
    destroy_uniform(s_ssao_noise_u_);
    destroy_uniform(s_gbuf_depth_u_);
    destroy_uniform(s_gbuf_normal_u_);
    if (::bgfx::isValid(::bgfx::ProgramHandle{ssao_blur_program_}))
        ::bgfx::destroy(::bgfx::ProgramHandle{ssao_blur_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{ssao_program_}))
        ::bgfx::destroy(::bgfx::ProgramHandle{ssao_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{prepass_program_}))
        ::bgfx::destroy(::bgfx::ProgramHandle{prepass_program_});

    // Post-process framebuffers and programs
    destroy_fb(blur_b_fb_);
    destroy_fb(blur_a_fb_);
    destroy_fb(bright_fb_);
    destroy_fb(hdr_fb_);
    if (::bgfx::isValid(::bgfx::TextureHandle{hdr_color_tex_})) ::bgfx::destroy(::bgfx::TextureHandle{hdr_color_tex_});
    if (::bgfx::isValid(::bgfx::IndexBufferHandle{fullscreen_ib_}))  ::bgfx::destroy(::bgfx::IndexBufferHandle{fullscreen_ib_});
    if (::bgfx::isValid(::bgfx::VertexBufferHandle{fullscreen_vb_})) ::bgfx::destroy(::bgfx::VertexBufferHandle{fullscreen_vb_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{tonemap_program_}))     ::bgfx::destroy(::bgfx::ProgramHandle{tonemap_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{blur_program_}))        ::bgfx::destroy(::bgfx::ProgramHandle{blur_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{bright_pass_program_})) ::bgfx::destroy(::bgfx::ProgramHandle{bright_pass_program_});

    // Clustered shading resources
    destroy_uniform(cluster_params_u_);
    destroy_uniform(cluster_params2_u_);
    destroy_uniform(compute_view_u_);
    if (::bgfx::isValid(::bgfx::ProgramHandle{depth_program_})) ::bgfx::destroy(::bgfx::ProgramHandle{depth_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{cull_program_}))  ::bgfx::destroy(::bgfx::ProgramHandle{cull_program_});

    auto destroy_dyn_ib = [](uint16_t h) {
        if (::bgfx::isValid(::bgfx::DynamicIndexBufferHandle{h})) ::bgfx::destroy(::bgfx::DynamicIndexBufferHandle{h});
    };
    destroy_dyn_ib(b_cluster_bounds_);
    destroy_dyn_ib(b_point_lights_);
    destroy_dyn_ib(b_spot_lights_);
    destroy_dyn_ib(b_p_light_indices_);
    destroy_dyn_ib(b_p_light_count_);
    destroy_dyn_ib(b_s_light_indices_);
    destroy_dyn_ib(b_s_light_count_);

    destroy_uniform(spot_lights_uniform_);
    destroy_uniform(point_lights_uniform_);
    destroy_uniform(light_counts_uniform_);
    destroy_uniform(shadow_params_uniform_);
    destroy_uniform(light_vp_uniform_);
    destroy_uniform(shadow_map_uniform_);
    destroy_uniform(normal_params_uniform_);
    destroy_uniform(normal_map_uniform_);
    destroy_uniform(ibl_params_uniform_);
    destroy_uniform(env_map_uniform_);
    destroy_uniform(camera_pos_uniform_);
    destroy_uniform(pbr_params_uniform_);
    destroy_uniform(ambient_color_uniform_);
    destroy_uniform(light_color_uniform_);
    destroy_uniform(light_dir_uniform_);
    destroy_uniform(color_uniform_);
    destroy_uniform(sampler_uniform_);
    destroy_uniform(skybox_sampler_uniform_);
    destroy_uniform(skybox_tint_uniform_);

    for (auto &sm : shadow_maps_)
    {
        if (::bgfx::isValid(::bgfx::FrameBufferHandle{sm.fb}))   ::bgfx::destroy(::bgfx::FrameBufferHandle{sm.fb});
        if (::bgfx::isValid(::bgfx::TextureHandle{sm.depth_tex})) ::bgfx::destroy(::bgfx::TextureHandle{sm.depth_tex});
        if (::bgfx::isValid(::bgfx::TextureHandle{sm.color_tex})) ::bgfx::destroy(::bgfx::TextureHandle{sm.color_tex});
    }
    shadow_maps_.clear();

    if (::bgfx::isValid(::bgfx::ProgramHandle{shadow_program_})) ::bgfx::destroy(::bgfx::ProgramHandle{shadow_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{skybox_program_})) ::bgfx::destroy(::bgfx::ProgramHandle{skybox_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{program_}))         ::bgfx::destroy(::bgfx::ProgramHandle{program_});

    ke_log_event ev = {KE_LOG_LEVEL_INFO, "bgfx", "bgfx shutdown"};
    if (logger_) logger_->log(logger_, &ev);
    ::bgfx::shutdown();
    return KE_OK;
}

ke_result BgfxRenderSystem::SetOrthographic(bool enabled) {
    orthographic_ = enabled;
    return KE_OK;
}

ke_result BgfxRenderSystem::SetViewTransform(const ke_mat4 *view, const ke_mat4 *proj)
{
    if (!view || !proj) return KE_ERROR_INVALID_ARGUMENT;
    memcpy(last_view_, view->m, sizeof(float) * 16);
    memcpy(last_proj_, proj->m, sizeof(float) * 16);

    // Extract near/far planes from standard projection matrix.
    // near = proj[14] / (proj[10] + 1)
    // far  = proj[14] / (proj[10] - 1)
    float n = proj->m[14] / (proj->m[10] + 1.0f);
    float f = proj->m[14] / (proj->m[10] - 1.0f);
    if (std::abs(n - near_z_) > 0.0001f || std::abs(f - far_z_) > 0.0001f) {
        near_z_ = n;
        far_z_  = f;
        bounds_dirty_ = true;
    }

    // Extract projection parameters for SSAO depth reconstruction.
    // Column-major layout: m[0] = proj[0][0], m[5] = proj[1][1].
    ssao_proj_info_[0] = (proj->m[0] != 0.f) ? (1.0f / proj->m[0]) : 1.0f;
    ssao_proj_info_[1] = (proj->m[5] != 0.f) ? (1.0f / proj->m[5]) : 1.0f;
    ::bgfx::setViewTransform(kPrepassView, view->m, proj->m);
    ::bgfx::setViewTransform(kSsaoView,    view->m, proj->m); // u_proj available in fs_ssao
    ::bgfx::setViewTransform(kSceneView,   view->m, proj->m);
    return KE_OK;
}

ke_result BgfxRenderSystem::Frame()
{
    // ── Clustered Culling ──────────────────────────────────────────────────────
    UpdateClusterBounds();
    DispatchLightCull();

    // ── SSAO passes ────────────────────────────────────────────────────────────
    if (ssao_enabled_ && gbuf_fb_ != kInvalidHandle)
    {
        ::bgfx::setViewFrameBuffer(kPrepassView,  ::bgfx::FrameBufferHandle{gbuf_fb_});
        ::bgfx::setViewClear(kPrepassView, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 0x00000000, 1.0f, 0);
        ::bgfx::setViewRect(kPrepassView,  0, 0, (uint16_t)view_w_, (uint16_t)view_h_);

        ::bgfx::setViewFrameBuffer(kSsaoView, ::bgfx::FrameBufferHandle{ssao_raw_fb_});
        ::bgfx::setViewClear(kSsaoView, BGFX_CLEAR_COLOR, 0xffffffff, 1.0f, 0);
        ::bgfx::setViewRect(kSsaoView, 0, 0, (uint16_t)view_w_, (uint16_t)view_h_);

        ::bgfx::setViewFrameBuffer(kSsaoBlurView, ::bgfx::FrameBufferHandle{ssao_blur_fb_});
        ::bgfx::setViewClear(kSsaoBlurView, BGFX_CLEAR_COLOR, 0xffffffff, 1.0f, 0);
        ::bgfx::setViewRect(kSsaoBlurView, 0, 0, (uint16_t)view_w_, (uint16_t)view_h_);

        SubmitSsao();
    }

    // ── Post-processing / scene routing ────────────────────────────────────────
    if (pp_enabled_ && hdr_fb_ != kInvalidHandle)
    {
        ::bgfx::setViewFrameBuffer(kSceneView,  ::bgfx::FrameBufferHandle{hdr_fb_});
        ::bgfx::setViewFrameBuffer(kSkyboxView, ::bgfx::FrameBufferHandle{hdr_fb_});
        SubmitPostProcess();
    }
    else
    {
        ::bgfx::setViewFrameBuffer(kSceneView,  ::bgfx::FrameBufferHandle{::bgfx::kInvalidHandle});
        ::bgfx::setViewFrameBuffer(kSkyboxView, ::bgfx::FrameBufferHandle{::bgfx::kInvalidHandle});
    }

    ::bgfx::touch(kSceneView);
    ::bgfx::touch(kSkyboxView);
    ::bgfx::frame();
    has_skybox_           = false;
    active_env_tex_       = kInvalidHandle;
    active_shadow_handle_ = kInvalidShadowHandle;
    // Lights are cleared each frame; the engine must re-submit them.
    point_lights_.clear();
    spot_lights_.clear();
    return KE_OK;
}

ke_result BgfxRenderSystem::ClearColor(float r, float g, float b, float a)
{
    uint32_t color = (uint32_t(r * 255.0F) << 24) | (uint32_t(g * 255.0F) << 16) |
                     (uint32_t(b * 255.0F) << 8)  | (uint32_t(a * 255.0F));
    ::bgfx::setViewClear(kSceneView, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, color, 1.0f, 0);
    return KE_OK;
}

ke_result BgfxRenderSystem::CreateMesh(const ke_vertex *verts, uint32_t vert_count,
                                        const uint16_t *indices, uint32_t index_count,
                                        ke_mesh_handle *out_handle)
{
    if (!verts || !indices || !out_handle || vert_count == 0 || index_count == 0) return KE_ERROR_INVALID_ARGUMENT;

    struct GpuVert {
        float x, y, z;
        uint32_t abgr;
        float nx, ny, nz;
        float u, v;
        float tx, ty, tz, tw; // tangent xyz + bitangent sign
    };
    std::vector<GpuVert> expanded(vert_count);
    for (uint32_t i = 0; i < vert_count; i++)
        expanded[i] = {verts[i].x, verts[i].y, verts[i].z, 0xffffffff,
                       verts[i].nx, verts[i].ny, verts[i].nz,
                       verts[i].u, verts[i].v,
                       verts[i].tx, verts[i].ty, verts[i].tz, verts[i].tw};

    ::bgfx::VertexLayout layout;
    layout.begin()
        .add(::bgfx::Attrib::Position,  3, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::Color0,    4, ::bgfx::AttribType::Uint8,  true)
        .add(::bgfx::Attrib::Normal,    3, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::TexCoord0, 2, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::Tangent,   4, ::bgfx::AttribType::Float)
        .end();

    MeshEntry entry;
    entry.vb = ::bgfx::createVertexBuffer(
        ::bgfx::copy(expanded.data(), (uint32_t)(sizeof(GpuVert) * vert_count)), layout).idx;
    entry.ib = ::bgfx::createIndexBuffer(
        ::bgfx::copy(indices, sizeof(uint16_t) * index_count)).idx;
    entry.index_count = index_count;

    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb}) ||
        !::bgfx::isValid(::bgfx::IndexBufferHandle{entry.ib}))
        return KE_ERROR_RENDER;

    meshes_.push_back(entry);
    *out_handle = (ke_mesh_handle)(meshes_.size() - 1);
    return KE_OK;
}

ke_result BgfxRenderSystem::DestroyMesh(ke_mesh_handle handle)
{
    if (handle >= (ke_mesh_handle)meshes_.size()) return KE_ERROR_INVALID_ARGUMENT;
    auto &entry = meshes_[handle];
    if (::bgfx::isValid(::bgfx::IndexBufferHandle{entry.ib}))  ::bgfx::destroy(::bgfx::IndexBufferHandle{entry.ib});
    if (::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb})) ::bgfx::destroy(::bgfx::VertexBufferHandle{entry.vb});
    entry.vb = kInvalidHandle;
    entry.ib = kInvalidHandle;
    return KE_OK;
}

// Generates a full RGBA8 mip chain (mip0|mip1|...) using a 2×2 box filter.
// Returns the packed buffer; sets *out_num_mips to the level count.
static std::vector<uint8_t> GenerateMips(uint32_t width, uint32_t height,
                                          const uint8_t *pixels, uint8_t *out_num_mips)
{
    uint32_t maxDim = width > height ? width : height;
    uint8_t  numMips = 0;
    for (uint32_t d = maxDim; d > 0; d >>= 1) ++numMips;

    uint32_t total = 0;
    { uint32_t w = width, h = height;
      for (uint8_t i = 0; i < numMips; ++i) {
          total += w * h * 4;
          w = w > 1 ? w >> 1 : 1;
          h = h > 1 ? h >> 1 : 1;
      }
    }

    std::vector<uint8_t> buf(total);
    std::memcpy(buf.data(), pixels, width * height * 4);

    const uint8_t *src = buf.data();
    uint32_t srcW = width, srcH = height;
    uint8_t *dst = buf.data() + width * height * 4;

    for (uint8_t mip = 1; mip < numMips; ++mip) {
        uint32_t dstW = srcW > 1 ? srcW >> 1 : 1;
        uint32_t dstH = srcH > 1 ? srcH >> 1 : 1;
        for (uint32_t y = 0; y < dstH; ++y) {
            for (uint32_t x = 0; x < dstW; ++x) {
                uint32_t x0 = x * 2, y0 = y * 2;
                uint32_t x1 = srcW > 1 ? x0 + 1 : x0;
                uint32_t y1 = srcH > 1 ? y0 + 1 : y0;
                const uint8_t *p00 = src + (y0 * srcW + x0) * 4;
                const uint8_t *p10 = src + (y0 * srcW + x1) * 4;
                const uint8_t *p01 = src + (y1 * srcW + x0) * 4;
                const uint8_t *p11 = src + (y1 * srcW + x1) * 4;
                for (int c = 0; c < 4; ++c)
                    dst[(y * dstW + x) * 4 + c] =
                        (uint8_t)((p00[c] + p10[c] + p01[c] + p11[c] + 2) >> 2);
            }
        }
        src = dst; dst += dstW * dstH * 4;
        srcW = dstW; srcH = dstH;
    }

    *out_num_mips = numMips;
    return buf;
}

ke_result BgfxRenderSystem::CreateTextureRgba(uint32_t width, uint32_t height,
                                               const uint8_t *pixels,
                                               ke_texture_handle *out_handle)
{
    if (!pixels || !out_handle || width == 0 || height == 0) return KE_ERROR_INVALID_ARGUMENT;
    uint8_t numMips;
    std::vector<uint8_t> mipData = GenerateMips(width, height, pixels, &numMips);
    uint16_t idx = ::bgfx::createTexture2D(
        (uint16_t)width, (uint16_t)height, numMips > 1, 1,
        ::bgfx::TextureFormat::RGBA8, 0,
        ::bgfx::copy(mipData.data(), (uint32_t)mipData.size())).idx;
    if (!::bgfx::isValid(::bgfx::TextureHandle{idx})) return KE_ERROR_RENDER;
    textures_.push_back({idx, true});
    *out_handle = (ke_texture_handle)(textures_.size() - 1);
    return KE_OK;
}

ke_result BgfxRenderSystem::DestroyTexture(ke_texture_handle handle)
{
    if (handle >= (ke_texture_handle)textures_.size()) return KE_ERROR_INVALID_ARGUMENT;
    auto &t = textures_[handle];
    if (::bgfx::isValid(::bgfx::TextureHandle{t.idx})) ::bgfx::destroy(::bgfx::TextureHandle{t.idx});
    t.idx   = kInvalidHandle;
    t.valid = false;
    return KE_OK;
}

ke_result BgfxRenderSystem::CreateCubemapRgba(uint32_t size, const uint8_t *data,
                                               ke_texture_handle *out_handle)
{
    if (!data || !out_handle || size == 0) return KE_ERROR_INVALID_ARGUMENT;

    // Generate mips for each of the 6 faces
    uint32_t faceBytes = size * size * 4u;
    uint8_t numMips;
    std::vector<std::vector<uint8_t>> faceMips(6);
    for (int f = 0; f < 6; ++f)
        faceMips[f] = GenerateMips(size, size, data + f * faceBytes, &numMips);

    // Per-mip face size table
    std::vector<uint32_t> mipFaceSize(numMips);
    { uint32_t s = size;
      for (uint8_t m = 0; m < numMips; ++m) {
          mipFaceSize[m] = s * s * 4u;
          s = s > 1 ? s >> 1 : 1;
      }
    }

    // bgfx cubemap layout: for each mip level, all 6 faces in order
    uint32_t total = 0;
    for (uint8_t m = 0; m < numMips; ++m) total += 6u * mipFaceSize[m];

    std::vector<uint8_t> cubeBuf(total);
    uint8_t *p = cubeBuf.data();
    uint32_t faceOffset = 0;
    for (uint8_t m = 0; m < numMips; ++m) {
        for (int f = 0; f < 6; ++f) {
            std::memcpy(p, faceMips[f].data() + faceOffset, mipFaceSize[m]);
            p += mipFaceSize[m];
        }
        faceOffset += mipFaceSize[m];
    }

    uint16_t idx = ::bgfx::createTextureCube(
        (uint16_t)size, numMips > 1, 1,
        ::bgfx::TextureFormat::RGBA8, 0,
        ::bgfx::copy(cubeBuf.data(), (uint32_t)cubeBuf.size())).idx;
    if (!::bgfx::isValid(::bgfx::TextureHandle{idx})) return KE_ERROR_RENDER;
    textures_.push_back({idx, true});
    *out_handle = (ke_texture_handle)(textures_.size() - 1);
    return KE_OK;
}

ke_result BgfxRenderSystem::SubmitSkybox(ke_texture_handle cubemap_handle)
{
    if (!::bgfx::isValid(::bgfx::ProgramHandle{skybox_program_})) return KE_ERROR_NOT_INITIALIZED;
    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{skybox_vb_})) return KE_ERROR_NOT_INITIALIZED;
    if (cubemap_handle >= (ke_texture_handle)textures_.size())     return KE_ERROR_INVALID_ARGUMENT;
    const auto &tex = textures_[cubemap_handle];
    if (!tex.valid) return KE_ERROR_INVALID_ARGUMENT;

    float rotView[16];
    memcpy(rotView, last_view_, sizeof(rotView));
    rotView[12] = 0.f; rotView[13] = 0.f; rotView[14] = 0.f;
    ::bgfx::setViewTransform(kSkyboxView, rotView, last_proj_);

    float tint[4] = {1.f, 1.f, 1.f, 1.f};
    ::bgfx::setUniform(::bgfx::UniformHandle{skybox_tint_uniform_}, tint);
    ::bgfx::setTexture(0, ::bgfx::UniformHandle{skybox_sampler_uniform_}, ::bgfx::TextureHandle{tex.idx});
    ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{skybox_vb_});
    ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{skybox_ib_});
    ::bgfx::setState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A | BGFX_STATE_DEPTH_TEST_LEQUAL);
    ::bgfx::submit(kSkyboxView, ::bgfx::ProgramHandle{skybox_program_});

    has_skybox_     = true;
    active_env_tex_ = tex.idx;
    return KE_OK;
}

ke_result BgfxRenderSystem::CreateMaterial(const ke_material *mat, ke_material_handle *out_handle)
{
    if (!mat || !out_handle) return KE_ERROR_INVALID_ARGUMENT;
    uint32_t tex  = (mat->albedo     < (ke_texture_handle)textures_.size()) ? mat->albedo     : 0;
    uint32_t nmap = (mat->normal_map < (ke_texture_handle)textures_.size()) ? mat->normal_map : 0;
    materials_.push_back({mat->r, mat->g, mat->b, mat->a, tex, mat->metallic, mat->roughness, nmap, true});
    *out_handle = (ke_material_handle)(materials_.size() - 1);
    return KE_OK;
}

ke_result BgfxRenderSystem::DestroyMaterial(ke_material_handle handle)
{
    if (handle >= (ke_material_handle)materials_.size()) return KE_ERROR_INVALID_ARGUMENT;
    materials_[handle].valid = false;
    return KE_OK;
}

ke_result BgfxRenderSystem::SubmitMesh(ke_mesh_handle mesh, ke_material_handle material, const ke_mat4 *transform)
{
    if (!transform) return KE_ERROR_INVALID_ARGUMENT;
    if (!::bgfx::isValid(::bgfx::ProgramHandle{program_})) return KE_ERROR_NOT_INITIALIZED;
    if (mesh     >= (ke_mesh_handle)meshes_.size())     return KE_ERROR_INVALID_ARGUMENT;
    if (material >= (ke_material_handle)materials_.size()) return KE_ERROR_INVALID_ARGUMENT;
    const auto &entry = meshes_[mesh];
    const auto &mat   = materials_[material];
    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb}) || !mat.valid) return KE_ERROR_INVALID_ARGUMENT;

    uint32_t tex_idx   = (mat.texture_handle < textures_.size()) ? mat.texture_handle : 0;
    uint32_t nmap_idx  = (mat.normal_map_handle < textures_.size()) ? mat.normal_map_handle : 0;
    float color[4]     = {mat.r, mat.g, mat.b, mat.a};
    float pbr_params[4]= {mat.metallic, mat.roughness, 0.f, 0.f};

    // ── Depth prepass (for culling/SSAO) ──────────────────────────────────────
    if (::bgfx::isValid(::bgfx::ProgramHandle{depth_program_}))
    {
        ::bgfx::setTransform(transform->m);
        ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
        ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
        ::bgfx::setState(BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS);
        ::bgfx::submit(kDepthView, ::bgfx::ProgramHandle{depth_program_});
    }

    // ── G-buffer prepass (if SSAO enabled) ────────────────────────────────────
    if (ssao_enabled_ && prepass_program_ != kInvalidHandle)
    {
        ::bgfx::setTransform(transform->m);
        ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
        ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
        ::bgfx::setState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A |
                         BGFX_STATE_WRITE_Z   | BGFX_STATE_DEPTH_TEST_LESS);
        ::bgfx::submit(kPrepassView, ::bgfx::ProgramHandle{prepass_program_});
    }

    // ── Main scene pass ────────────────────────────────────────────────────────
    ::bgfx::setUniform(::bgfx::UniformHandle{color_uniform_},         color);
    ::bgfx::setUniform(::bgfx::UniformHandle{light_dir_uniform_},     light_dir_);
    ::bgfx::setUniform(::bgfx::UniformHandle{light_color_uniform_},   light_color_);
    ::bgfx::setUniform(::bgfx::UniformHandle{ambient_color_uniform_}, ambient_color_);
    ::bgfx::setUniform(::bgfx::UniformHandle{pbr_params_uniform_},    pbr_params);
    ::bgfx::setUniform(::bgfx::UniformHandle{camera_pos_uniform_},    camera_pos_);

    // Cluster Params
    float clusterParams[4] = {(float)cluster_config_.grid_x, (float)cluster_config_.grid_y,
                              (float)cluster_config_.grid_z, (float)cluster_config_.max_lights_per_cluster};
    ::bgfx::setUniform(::bgfx::UniformHandle{cluster_params_u_}, clusterParams);

    float clusterParams2[4] = {(float)std::min(point_lights_.size(), (size_t)64),
                               (float)std::min(spot_lights_.size(), (size_t)64), near_z_, far_z_};
    ::bgfx::setUniform(::bgfx::UniformHandle{cluster_params2_u_}, clusterParams2);

    if (has_skybox_ && active_env_tex_ != kInvalidHandle)
    {
        float ibl_params[4] = {1.f, 0.f, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{ibl_params_uniform_}, ibl_params);
        ::bgfx::setTexture(1, ::bgfx::UniformHandle{env_map_uniform_}, ::bgfx::TextureHandle{active_env_tex_});
    }
    else
    {
        float ibl_params[4] = {0.f, 0.f, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{ibl_params_uniform_}, ibl_params);
        ::bgfx::setTexture(1, ::bgfx::UniformHandle{env_map_uniform_}, ::bgfx::TextureHandle{textures_[0].idx});
    }

    if (active_shadow_handle_ != kInvalidShadowHandle)
    {
        float shadow_params[4] = {1.f, 0.f, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{shadow_params_uniform_}, shadow_params);
        ::bgfx::setUniform(::bgfx::UniformHandle{light_vp_uniform_}, active_light_vp_);
        ::bgfx::setTexture(2, ::bgfx::UniformHandle{shadow_map_uniform_},
            ::bgfx::TextureHandle{shadow_maps_[active_shadow_handle_].color_tex});
    }
    else
    {
        float shadow_params[4] = {0.f, 0.f, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{shadow_params_uniform_}, shadow_params);
        float identity[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
        ::bgfx::setUniform(::bgfx::UniformHandle{light_vp_uniform_}, identity);
        ::bgfx::setTexture(2, ::bgfx::UniformHandle{shadow_map_uniform_},
            ::bgfx::TextureHandle{textures_[0].idx});
    }

    if (nmap_idx != 0)
    {
        float normal_params[4] = {1.f, 0.f, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{normal_params_uniform_}, normal_params);
        ::bgfx::setTexture(3, ::bgfx::UniformHandle{normal_map_uniform_}, ::bgfx::TextureHandle{textures_[nmap_idx].idx});
    }
    else
    {
        float normal_params[4] = {0.f, 0.f, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{normal_params_uniform_}, normal_params);
        ::bgfx::setTexture(3, ::bgfx::UniformHandle{normal_map_uniform_}, ::bgfx::TextureHandle{textures_[0].idx});
    }

    // SSAO blurred occlusion texture (slot 4) and state uniform
    {
        float ssao_state[4] = {
            ssao_enabled_ ? 1.f : 0.f,
            (view_w_ > 0) ? 1.f / (float)view_w_ : 0.f,
            (view_h_ > 0) ? 1.f / (float)view_h_ : 0.f,
            0.f
        };
        ::bgfx::setUniform(::bgfx::UniformHandle{ssao_state_u_}, ssao_state);
        uint16_t ao_tex = (ssao_enabled_ && ssao_blur_tex_ != kInvalidHandle)
                              ? ssao_blur_tex_ : textures_[0].idx;
        ::bgfx::setTexture(4, ::bgfx::UniformHandle{s_ssao_blurred_u_}, ::bgfx::TextureHandle{ao_tex});
    }

    // Point lights uniform array (2 vec4 per light, up to 64)
    {
        static float pl_data[128 * 4] = {};
        uint32_t pCount = (uint32_t)std::min(point_lights_.size(), (size_t)64);
        for (uint32_t i = 0; i < pCount; ++i)
        {
            const auto &l = point_lights_[i];
            pl_data[i * 8 + 0] = l.pos_x;
            pl_data[i * 8 + 1] = l.pos_y;
            pl_data[i * 8 + 2] = l.pos_z;
            pl_data[i * 8 + 3] = l.radius;
            pl_data[i * 8 + 4] = l.r * l.intensity;
            pl_data[i * 8 + 5] = l.g * l.intensity;
            pl_data[i * 8 + 6] = l.b * l.intensity;
            pl_data[i * 8 + 7] = 0.f;
        }
        ::bgfx::setUniform(::bgfx::UniformHandle{point_lights_uniform_}, pl_data, 128);
    }

    // Spot lights uniform array (3 vec4 per light, up to 64)
    {
        static float sl_data[192 * 4] = {};
        uint32_t sCount = (uint32_t)std::min(spot_lights_.size(), (size_t)64);
        for (uint32_t j = 0; j < sCount; ++j)
        {
            const auto &l = spot_lights_[j];
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
        ::bgfx::setUniform(::bgfx::UniformHandle{spot_lights_uniform_}, sl_data, 192);
    }

    ::bgfx::setTexture(0, ::bgfx::UniformHandle{sampler_uniform_}, ::bgfx::TextureHandle{textures_[tex_idx].idx});
    ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
    ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
    ::bgfx::setTransform(transform->m);
    ::bgfx::setState(BGFX_STATE_DEFAULT);
    ::bgfx::submit(kSceneView, ::bgfx::ProgramHandle{program_});
    return KE_OK;
}

static void MulMat4(const float *a, const float *b, float *r)
{
    for (int i = 0; i < 4; ++i)
        for (int j = 0; j < 4; ++j)
        {
            r[i * 4 + j] = 0.f;
            for (int k = 0; k < 4; ++k)
                r[i * 4 + j] += a[i * 4 + k] * b[k * 4 + j];
        }
}

ke_result BgfxRenderSystem::CreateShadowMap(uint32_t w, uint32_t h, ke_shadow_map_handle *out_handle)
{
    if (!out_handle || w == 0 || h == 0) return KE_ERROR_INVALID_ARGUMENT;

    // R32F color texture — stores depth value written by fs_shadow.
    ::bgfx::TextureHandle color = ::bgfx::createTexture2D(
        (uint16_t)w, (uint16_t)h, false, 1,
        ::bgfx::TextureFormat::R32F, BGFX_TEXTURE_RT);

    // D16 depth texture — drives hardware depth test during the shadow pass.
    ::bgfx::TextureHandle depth = ::bgfx::createTexture2D(
        (uint16_t)w, (uint16_t)h, false, 1,
        ::bgfx::TextureFormat::D16, BGFX_TEXTURE_RT_WRITE_ONLY);

    if (!::bgfx::isValid(color) || !::bgfx::isValid(depth))
    {
        if (::bgfx::isValid(color)) ::bgfx::destroy(color);
        if (::bgfx::isValid(depth)) ::bgfx::destroy(depth);
        return KE_ERROR_RENDER;
    }

    ::bgfx::TextureHandle attachments[2] = {color, depth};
    ::bgfx::FrameBufferHandle fb = ::bgfx::createFrameBuffer(2, attachments, false);
    if (!::bgfx::isValid(fb))
    {
        ::bgfx::destroy(color);
        ::bgfx::destroy(depth);
        return KE_ERROR_RENDER;
    }

    shadow_maps_.push_back({color.idx, depth.idx, fb.idx, w, h, true});
    *out_handle = (ke_shadow_map_handle)(shadow_maps_.size() - 1);
    return KE_OK;
}

ke_result BgfxRenderSystem::DestroyShadowMap(ke_shadow_map_handle handle)
{
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid)
        return KE_ERROR_INVALID_ARGUMENT;
    auto &sm = shadow_maps_[handle];
    if (::bgfx::isValid(::bgfx::FrameBufferHandle{sm.fb}))   ::bgfx::destroy(::bgfx::FrameBufferHandle{sm.fb});
    if (::bgfx::isValid(::bgfx::TextureHandle{sm.depth_tex})) ::bgfx::destroy(::bgfx::TextureHandle{sm.depth_tex});
    if (::bgfx::isValid(::bgfx::TextureHandle{sm.color_tex})) ::bgfx::destroy(::bgfx::TextureHandle{sm.color_tex});
    sm = {};
    return KE_OK;
}

ke_result BgfxRenderSystem::BeginShadowPass(ke_shadow_map_handle handle,
                                              const ke_mat4 *light_view, const ke_mat4 *light_proj)
{
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid)
        return KE_ERROR_INVALID_ARGUMENT;
    if (!light_view || !light_proj) return KE_ERROR_INVALID_ARGUMENT;

    const auto &sm = shadow_maps_[handle];

    ::bgfx::setViewFrameBuffer(0, ::bgfx::FrameBufferHandle{sm.fb});
    ::bgfx::setViewRect(0, 0, 0, (uint16_t)sm.width, (uint16_t)sm.height);
    ::bgfx::setViewTransform(0, light_view->m, light_proj->m);

    // Clear R32F to 1.0 (max depth) via palette, and clear hardware depth to 1.0.
    ::bgfx::setPaletteColor(0, 1.0f, 0.0f, 0.0f, 0.0f);
    ::bgfx::setViewClear(0, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 1.0f, 0, 0);

    active_shadow_handle_ = handle;
    MulMat4(light_view->m, light_proj->m, active_light_vp_);
    return KE_OK;
}

ke_result BgfxRenderSystem::SubmitMeshShadow(ke_mesh_handle mesh, const ke_mat4 *transform)
{
    if (!::bgfx::isValid(::bgfx::ProgramHandle{shadow_program_})) return KE_ERROR_NOT_INITIALIZED;
    if (!transform) return KE_ERROR_INVALID_ARGUMENT;
    if (mesh >= (ke_mesh_handle)meshes_.size()) return KE_ERROR_INVALID_ARGUMENT;
    const auto &entry = meshes_[mesh];
    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb})) return KE_ERROR_INVALID_ARGUMENT;

    ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
    ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
    ::bgfx::setTransform(transform->m);
    ::bgfx::setState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS);
    ::bgfx::submit(0, ::bgfx::ProgramHandle{shadow_program_});
    return KE_OK;
}

ke_result BgfxRenderSystem::EndShadowPass()
{
    // active_shadow_handle_ stays set so SubmitMesh can bind the shadow map.
    return KE_OK;
}

ke_result BgfxRenderSystem::SetShadowMap(ke_shadow_map_handle handle)
{
    if (handle == KE_INVALID_SHADOW_MAP_HANDLE)
    {
        active_shadow_handle_ = kInvalidShadowHandle;
        return KE_OK;
    }
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid)
        return KE_ERROR_INVALID_ARGUMENT;
    active_shadow_handle_ = handle;
    return KE_OK;
}

ke_result BgfxRenderSystem::SetDirectionalLight(const ke_directional_light *light)
{
    if (!light) return KE_ERROR_INVALID_ARGUMENT;
    light_dir_[0] = light->dir_x; light_dir_[1] = light->dir_y; light_dir_[2] = light->dir_z; light_dir_[3] = 0.f;
    light_color_[0] = light->r * light->intensity; light_color_[1] = light->g * light->intensity; light_color_[2] = light->b * light->intensity; light_color_[3] = 0.f;
    return KE_OK;
}

ke_result BgfxRenderSystem::SetAmbientLight(float r, float g, float b)
{
    ambient_color_[0] = r; ambient_color_[1] = g; ambient_color_[2] = b; ambient_color_[3] = 0.f;
    return KE_OK;
}

ke_result BgfxRenderSystem::SetCameraPos(float x, float y, float z)
{
    camera_pos_[0] = x; camera_pos_[1] = y; camera_pos_[2] = z; camera_pos_[3] = 0.f;
    return KE_OK;
}

ke_result BgfxRenderSystem::SetPointLights(const ke_point_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    point_lights_.assign(lights, lights + count);

    struct GpuPointLight { float pos_r[4]; float color[4]; };
    std::vector<GpuPointLight> gpuLights(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        gpuLights[i].pos_r[0] = lights[i].pos_x;
        gpuLights[i].pos_r[1] = lights[i].pos_y;
        gpuLights[i].pos_r[2] = lights[i].pos_z;
        gpuLights[i].pos_r[3] = lights[i].radius;
        gpuLights[i].color[0] = lights[i].r * lights[i].intensity;
        gpuLights[i].color[1] = lights[i].g * lights[i].intensity;
        gpuLights[i].color[2] = lights[i].b * lights[i].intensity;
        gpuLights[i].color[3] = 0.f;
    }

    if (count > 0)
    {
        ::bgfx::update(::bgfx::DynamicIndexBufferHandle{b_point_lights_}, 0,
                       ::bgfx::copy(gpuLights.data(), (uint32_t)(count * sizeof(GpuPointLight))));
    }
    return KE_OK;
}

ke_result BgfxRenderSystem::SetSpotLights(const ke_spot_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    spot_lights_.assign(lights, lights + count);

    struct GpuSpotLight { float pos_r[4]; float dir_cosI[4]; float color_cosO[4]; };
    std::vector<GpuSpotLight> gpuLights(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        gpuLights[i].pos_r[0] = lights[i].pos_x;
        gpuLights[i].pos_r[1] = lights[i].pos_y;
        gpuLights[i].pos_r[2] = lights[i].pos_z;
        gpuLights[i].pos_r[3] = lights[i].range;
        gpuLights[i].dir_cosI[0] = lights[i].dir_x;
        gpuLights[i].dir_cosI[1] = lights[i].dir_y;
        gpuLights[i].dir_cosI[2] = lights[i].dir_z;
        gpuLights[i].dir_cosI[3] = cosf(lights[i].inner_angle);
        gpuLights[i].color_cosO[0] = lights[i].r * lights[i].intensity;
        gpuLights[i].color_cosO[1] = lights[i].g * lights[i].intensity;
        gpuLights[i].color_cosO[2] = lights[i].b * lights[i].intensity;
        gpuLights[i].color_cosO[3] = cosf(lights[i].outer_angle);
    }

    if (count > 0)
    {
        ::bgfx::update(::bgfx::DynamicIndexBufferHandle{b_spot_lights_}, 0,
                       ::bgfx::copy(gpuLights.data(), (uint32_t)(count * sizeof(GpuSpotLight))));
    }
    return KE_OK;
}

// ── Post-processing ────────────────────────────────────────────────────────

ke_result BgfxRenderSystem::SetupPostProcess()
{
    auto load_shader = [&](const char *name) -> ::bgfx::ShaderHandle {
        std::string path = shader_path_ + "/" + name + ".bin";
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open()) return ::bgfx::ShaderHandle{::bgfx::kInvalidHandle};
        auto size = (uint32_t)file.tellg();
        file.seekg(0);
        const ::bgfx::Memory *mem = ::bgfx::alloc(size + 1);
        file.read(reinterpret_cast<char *>(mem->data), size);
        mem->data[size] = '\0';
        return ::bgfx::createShader(mem);
    };

    // Load post-process programs (optional — PP is off by default).
    auto load_pp_program = [&](const char *vs_name, const char *fs_name) -> uint16_t {
        ::bgfx::ShaderHandle vs = load_shader(vs_name);
        ::bgfx::ShaderHandle fs = load_shader(fs_name);
        if (!::bgfx::isValid(vs) || !::bgfx::isValid(fs))
        {
            if (::bgfx::isValid(vs)) ::bgfx::destroy(vs);
            if (::bgfx::isValid(fs)) ::bgfx::destroy(fs);
            return kInvalidHandle;
        }
        ::bgfx::ProgramHandle prog = ::bgfx::createProgram(vs, fs, true);
        return ::bgfx::isValid(prog) ? prog.idx : kInvalidHandle;
    };

    bright_pass_program_ = load_pp_program("vs_fullscreen", "fs_bright_pass");
    blur_program_        = load_pp_program("vs_fullscreen", "fs_blur");
    tonemap_program_     = load_pp_program("vs_fullscreen", "fs_tonemap");

    if (bright_pass_program_ == kInvalidHandle ||
        blur_program_        == kInvalidHandle ||
        tonemap_program_     == kInvalidHandle)
    {
        ke_log_event ev = {KE_LOG_LEVEL_WARNING, "bgfx", "Post-process shaders not found — PP disabled"};
        if (logger_) logger_->log(logger_, &ev);
        return KE_OK; // non-fatal
    }

    // Fullscreen triangle (position-only, z=0).
    ::bgfx::VertexLayout pos3;
    pos3.begin().add(::bgfx::Attrib::Position, 3, ::bgfx::AttribType::Float).end();
    static const float kFSVerts[9] = {-1.f,-1.f,0.f,  3.f,-1.f,0.f,  -1.f,3.f,0.f};
    static const uint16_t kFSIdx[3] = {0, 1, 2};
    fullscreen_vb_ = ::bgfx::createVertexBuffer(::bgfx::copy(kFSVerts, sizeof(kFSVerts)), pos3).idx;
    fullscreen_ib_ = ::bgfx::createIndexBuffer(::bgfx::copy(kFSIdx, sizeof(kFSIdx))).idx;

    // HDR framebuffer: RGBA16F color + D24 depth (full resolution).
    ::bgfx::TextureHandle hdr_color = ::bgfx::createTexture2D(
        (uint16_t)view_w_, (uint16_t)view_h_, false, 1,
        ::bgfx::TextureFormat::RGBA16F, BGFX_TEXTURE_RT);
    ::bgfx::TextureHandle hdr_depth = ::bgfx::createTexture2D(
        (uint16_t)view_w_, (uint16_t)view_h_, false, 1,
        ::bgfx::TextureFormat::D24, BGFX_TEXTURE_RT_WRITE_ONLY);

    if (!::bgfx::isValid(hdr_color) || !::bgfx::isValid(hdr_depth))
    {
        if (::bgfx::isValid(hdr_color)) ::bgfx::destroy(hdr_color);
        if (::bgfx::isValid(hdr_depth)) ::bgfx::destroy(hdr_depth);
        ke_log_event ev = {KE_LOG_LEVEL_WARNING, "bgfx", "HDR framebuffer creation failed — PP disabled"};
        if (logger_) logger_->log(logger_, &ev);
        return KE_OK;
    }

    ::bgfx::TextureHandle hdr_attachments[2] = {hdr_color, hdr_depth};
    ::bgfx::FrameBufferHandle hdr_fb = ::bgfx::createFrameBuffer(2, hdr_attachments, false);
    if (!::bgfx::isValid(hdr_fb))
    {
        ::bgfx::destroy(hdr_color);
        ::bgfx::destroy(hdr_depth);
        return KE_OK;
    }
    hdr_fb_        = hdr_fb.idx;
    hdr_color_tex_ = hdr_color.idx;
    // Destroy depth separately — it's not used for sampling.
    ::bgfx::destroy(hdr_depth);

    // Half-resolution for bloom passes.
    pp_w_ = (view_w_ + 1) / 2;
    pp_h_ = (view_h_ + 1) / 2;

    auto make_color_fb = [&](int w, int h) -> uint16_t {
        ::bgfx::TextureHandle tex = ::bgfx::createTexture2D(
            (uint16_t)w, (uint16_t)h, false, 1,
            ::bgfx::TextureFormat::RGBA16F, BGFX_TEXTURE_RT);
        if (!::bgfx::isValid(tex)) return kInvalidHandle;
        ::bgfx::FrameBufferHandle fb = ::bgfx::createFrameBuffer(1, &tex, true);
        return ::bgfx::isValid(fb) ? fb.idx : kInvalidHandle;
    };

    bright_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_a_fb_ = make_color_fb(pp_w_, pp_h_);
    blur_b_fb_ = make_color_fb(pp_w_, pp_h_);

    // Post-process uniforms.
    hdr_tex_uniform_       = ::bgfx::createUniform("s_hdrTex",       ::bgfx::UniformType::Sampler).idx;
    bloom_tex_uniform_     = ::bgfx::createUniform("s_bloomTex",     ::bgfx::UniformType::Sampler).idx;
    blur_tex_uniform_      = ::bgfx::createUniform("s_blurTex",      ::bgfx::UniformType::Sampler).idx;
    bloom_params_uniform_  = ::bgfx::createUniform("u_bloomParams",  ::bgfx::UniformType::Vec4).idx;
    blur_params_uniform_   = ::bgfx::createUniform("u_blurParams",   ::bgfx::UniformType::Vec4).idx;
    tonemap_params_uniform_= ::bgfx::createUniform("u_tonemapParams",::bgfx::UniformType::Vec4).idx;

    ke_log_event ev = {KE_LOG_LEVEL_INFO, "bgfx", "Post-process pipeline ready"};
    if (logger_) logger_->log(logger_, &ev);
    return KE_OK;
}

ke_result BgfxRenderSystem::SetTonemapping(bool enabled, float exposure, float gamma)
{
    if (enabled && hdr_fb_ == kInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    pp_enabled_ = enabled;
    exposure_   = exposure;
    gamma_      = gamma;
    return KE_OK;
}

ke_result BgfxRenderSystem::SetBloom(bool enabled, float threshold, float intensity)
{
    if (enabled && bright_fb_ == kInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    bloom_enabled_   = enabled;
    bloom_threshold_ = threshold;
    bloom_intensity_ = intensity;
    return KE_OK;
}

ke_result BgfxRenderSystem::SubmitPostProcess()
{
    auto submit_fs = [&](uint8_t view, uint16_t fb, int w, int h, uint16_t prog) {
        if (fb != kInvalidHandle)
        {
            ::bgfx::setViewFrameBuffer(view, ::bgfx::FrameBufferHandle{fb});
            ::bgfx::setViewClear(view, BGFX_CLEAR_COLOR, 0x000000ff, 1.0f, 0);
        }
        else
        {
            ::bgfx::setViewFrameBuffer(view, ::bgfx::FrameBufferHandle{::bgfx::kInvalidHandle});
            ::bgfx::setViewClear(view, BGFX_CLEAR_NONE);
        }
        ::bgfx::setViewRect(view, 0, 0, (uint16_t)w, (uint16_t)h);
        ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{fullscreen_vb_});
        ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{fullscreen_ib_});
        ::bgfx::setState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A);
        ::bgfx::submit(view, ::bgfx::ProgramHandle{prog});
    };

    // Bloom passes (views 6–8): bright-pass → blur H → blur V.
    uint16_t bloom_result_tex = textures_[0].idx; // black/white fallback
    if (bloom_enabled_ && bright_fb_ != kInvalidHandle)
    {
        // View 6: bright-pass.
        float bp[4] = {bloom_threshold_, 0.f, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{bloom_params_uniform_}, bp);
        ::bgfx::setTexture(0, ::bgfx::UniformHandle{hdr_tex_uniform_},
            ::bgfx::TextureHandle{hdr_color_tex_});
        submit_fs(kBrightView, bright_fb_, pp_w_, pp_h_, bright_pass_program_);

        // View 7: blur horizontal.
        float bh[4] = {1.f / (float)pp_w_, 0.f, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{blur_params_uniform_}, bh);
        ::bgfx::setTexture(0, ::bgfx::UniformHandle{blur_tex_uniform_},
            ::bgfx::getTexture(::bgfx::FrameBufferHandle{bright_fb_}));
        submit_fs(kBlurHView, blur_a_fb_, pp_w_, pp_h_, blur_program_);

        // View 8: blur vertical.
        float bv[4] = {0.f, 1.f / (float)pp_h_, 0.f, 0.f};
        ::bgfx::setUniform(::bgfx::UniformHandle{blur_params_uniform_}, bv);
        ::bgfx::setTexture(0, ::bgfx::UniformHandle{blur_tex_uniform_},
            ::bgfx::getTexture(::bgfx::FrameBufferHandle{blur_a_fb_}));
        submit_fs(kBlurVView, blur_b_fb_, pp_w_, pp_h_, blur_program_);

        bloom_result_tex = ::bgfx::getTexture(::bgfx::FrameBufferHandle{blur_b_fb_}).idx;
    }

    // View 9: tonemap composite → backbuffer.
    float tp[4] = {exposure_, bloom_enabled_ ? bloom_intensity_ : 0.f, 1.f / gamma_, 0.f};
    ::bgfx::setUniform(::bgfx::UniformHandle{tonemap_params_uniform_}, tp);
    ::bgfx::setTexture(0, ::bgfx::UniformHandle{hdr_tex_uniform_},
        ::bgfx::TextureHandle{hdr_color_tex_});
    ::bgfx::setTexture(1, ::bgfx::UniformHandle{bloom_tex_uniform_},
        ::bgfx::TextureHandle{bloom_result_tex});
    submit_fs(kTonemapView, kInvalidHandle, view_w_, view_h_, tonemap_program_);

    return KE_OK;
}

ke_result BgfxRenderSystem::SetupSsao()
{
    auto load_shader = [&](const char *name) -> ::bgfx::ShaderHandle {
        std::string path = shader_path_ + "/" + name + ".bin";
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open()) return ::bgfx::ShaderHandle{::bgfx::kInvalidHandle};
        auto size = file.tellg();
        file.seekg(0);
        const ::bgfx::Memory *mem = ::bgfx::alloc((uint32_t)size);
        file.read(reinterpret_cast<char *>(mem->data), size);
        return ::bgfx::createShader(mem);
    };

    auto load_program = [&](const char *vs, const char *fs) -> uint16_t {
        auto v = load_shader(vs);
        auto f = load_shader(fs);
        if (!::bgfx::isValid(v) || !::bgfx::isValid(f)) {
            if (::bgfx::isValid(v)) ::bgfx::destroy(v);
            if (::bgfx::isValid(f)) ::bgfx::destroy(f);
            return kInvalidHandle;
        }
        return ::bgfx::createProgram(v, f, true).idx;
    };

    prepass_program_    = load_program("vs_prepass",   "fs_prepass");
    ssao_program_       = load_program("vs_screen",    "fs_ssao");
    ssao_blur_program_  = load_program("vs_screen",    "fs_ssao_blur");

    // ── SSAO hemisphere kernel ─────────────────────────────────────────────────
    // Fixed seed for reproducible results.
    srand(42);
    auto rnd01 = []() -> float { return (float)rand() / (float)RAND_MAX; };
    auto rnd11 = []() -> float { return (float)rand() / (float)RAND_MAX * 2.f - 1.f; };

    for (uint32_t i = 0; i < kSsaoKernelSize; ++i)
    {
        float x = rnd11(), y = rnd11(), z = rnd01();
        float len = sqrtf(x*x + y*y + z*z);
        if (len < 0.0001f) { x = 0; y = 0; z = 1; len = 1; }
        x /= len; y /= len; z /= len;
        // Accelerate interpolation toward hemisphere surface.
        float scale = (float)i / (float)kSsaoKernelSize;
        scale = 0.1f + scale * scale * 0.9f;
        ssao_kernel_data_[i * 4 + 0] = x * scale;
        ssao_kernel_data_[i * 4 + 1] = y * scale;
        ssao_kernel_data_[i * 4 + 2] = z * scale;
        ssao_kernel_data_[i * 4 + 3] = 0.f;
    }

    // ── 4×4 random rotation noise texture (XY plane vectors) ──────────────────
    uint8_t noise_pixels[4 * 4 * 4]; // 16 pixels × RGBA8
    for (int i = 0; i < 16; ++i)
    {
        float rx = rnd11(), ry = rnd11();
        float rlen = sqrtf(rx*rx + ry*ry);
        if (rlen > 0.0001f) { rx /= rlen; ry /= rlen; }
        noise_pixels[i * 4 + 0] = (uint8_t)((rx * 0.5f + 0.5f) * 255.f);
        noise_pixels[i * 4 + 1] = (uint8_t)((ry * 0.5f + 0.5f) * 255.f);
        noise_pixels[i * 4 + 2] = 128;
        noise_pixels[i * 4 + 3] = 255;
    }
    ssao_noise_tex_ = ::bgfx::createTexture2D(
        4, 4, false, 1, ::bgfx::TextureFormat::RGBA8,
        BGFX_SAMPLER_POINT, // wrap is the default UV mode
        ::bgfx::copy(noise_pixels, sizeof(noise_pixels))).idx;

    // ── Uniforms ───────────────────────────────────────────────────────────────
    s_gbuf_normal_u_    = ::bgfx::createUniform("s_gbufNormal",    ::bgfx::UniformType::Sampler).idx;
    s_gbuf_depth_u_     = ::bgfx::createUniform("s_gbufDepth",     ::bgfx::UniformType::Sampler).idx;
    s_ssao_noise_u_     = ::bgfx::createUniform("s_ssaoNoise",     ::bgfx::UniformType::Sampler).idx;
    s_ssao_input_u_     = ::bgfx::createUniform("s_ssaoInput",     ::bgfx::UniformType::Sampler).idx;
    s_ssao_blurred_u_   = ::bgfx::createUniform("s_ssaoBlurred",   ::bgfx::UniformType::Sampler).idx;
    ssao_kernel_u_      = ::bgfx::createUniform("u_ssaoKernel",    ::bgfx::UniformType::Vec4, kSsaoKernelSize).idx;
    ssao_params_u_      = ::bgfx::createUniform("u_ssaoParams",    ::bgfx::UniformType::Vec4).idx;
    ssao_proj_info_u_   = ::bgfx::createUniform("u_ssaoProjInfo",  ::bgfx::UniformType::Vec4).idx;
    ssao_blur_params_u_ = ::bgfx::createUniform("u_ssaoBlurParams",::bgfx::UniformType::Vec4).idx;
    ssao_state_u_       = ::bgfx::createUniform("u_ssaoState",     ::bgfx::UniformType::Vec4).idx;

    // ── G-buffer framebuffer ───────────────────────────────────────────────────
    // Attachment 0: RGBA8 (view-space normals), Attachment 1: R16F (linear depth).
    // Attachment 2: D24S8 for depth testing (write-only, not sampled).
    ::bgfx::TextureHandle gbuf_texs[3] = {
        ::bgfx::createTexture2D((uint16_t)view_w_, (uint16_t)view_h_, false, 1,
            ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT),
        ::bgfx::createTexture2D((uint16_t)view_w_, (uint16_t)view_h_, false, 1,
            ::bgfx::TextureFormat::R16F,  BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT),
        ::bgfx::createTexture2D((uint16_t)view_w_, (uint16_t)view_h_, false, 1,
            ::bgfx::TextureFormat::D24S8, BGFX_TEXTURE_RT_WRITE_ONLY),
    };
    gbuf_fb_ = ::bgfx::createFrameBuffer(3, gbuf_texs, true).idx;
    gbuf_normal_tex_    = ::bgfx::getTexture(::bgfx::FrameBufferHandle{gbuf_fb_}, 0).idx;
    gbuf_lin_depth_tex_ = ::bgfx::getTexture(::bgfx::FrameBufferHandle{gbuf_fb_}, 1).idx;

    // ── SSAO raw + blur framebuffers ───────────────────────────────────────────
    ::bgfx::TextureHandle ssao_raw_t = ::bgfx::createTexture2D(
        (uint16_t)view_w_, (uint16_t)view_h_, false, 1,
        ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT);
    ssao_raw_fb_  = ::bgfx::createFrameBuffer(1, &ssao_raw_t, true).idx;
    ssao_raw_tex_ = ::bgfx::getTexture(::bgfx::FrameBufferHandle{ssao_raw_fb_}).idx;

    ::bgfx::TextureHandle ssao_blur_t = ::bgfx::createTexture2D(
        (uint16_t)view_w_, (uint16_t)view_h_, false, 1,
        ::bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_RT | BGFX_SAMPLER_POINT);
    ssao_blur_fb_  = ::bgfx::createFrameBuffer(1, &ssao_blur_t, true).idx;
    ssao_blur_tex_ = ::bgfx::getTexture(::bgfx::FrameBufferHandle{ssao_blur_fb_}).idx;

    return KE_OK;
}

ke_result BgfxRenderSystem::SubmitSsao()
{
    if (!ssao_enabled_) return KE_OK;
    if (gbuf_normal_tex_ == kInvalidHandle || ssao_raw_tex_ == kInvalidHandle) return KE_OK;

    // ── View kSsaoView: compute raw SSAO occlusion ─────────────────────────────
    float ssao_params[4]    = {ssao_radius_, ssao_bias_, ssao_strength_, 0.f};
    float ssao_proj_info[4] = {ssao_proj_info_[0], ssao_proj_info_[1], 0.f, 0.f};

    ::bgfx::setUniform(::bgfx::UniformHandle{ssao_kernel_u_},    ssao_kernel_data_, kSsaoKernelSize);
    ::bgfx::setUniform(::bgfx::UniformHandle{ssao_params_u_},    ssao_params);
    ::bgfx::setUniform(::bgfx::UniformHandle{ssao_proj_info_u_}, ssao_proj_info);
    ::bgfx::setTexture(0, ::bgfx::UniformHandle{s_gbuf_normal_u_}, ::bgfx::TextureHandle{gbuf_normal_tex_});
    ::bgfx::setTexture(1, ::bgfx::UniformHandle{s_gbuf_depth_u_},  ::bgfx::TextureHandle{gbuf_lin_depth_tex_});
    ::bgfx::setTexture(2, ::bgfx::UniformHandle{s_ssao_noise_u_},  ::bgfx::TextureHandle{ssao_noise_tex_});
    ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{fullscreen_vb_});
    ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{fullscreen_ib_});
    ::bgfx::setState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A);
    ::bgfx::submit(kSsaoView, ::bgfx::ProgramHandle{ssao_program_});

    // ── View kSsaoBlurView: 5×5 box blur ──────────────────────────────────────
    float blur_params[4] = {
        (view_w_ > 0) ? 1.f / (float)view_w_ : 0.f,
        (view_h_ > 0) ? 1.f / (float)view_h_ : 0.f,
        0.f, 0.f
    };
    ::bgfx::setUniform(::bgfx::UniformHandle{ssao_blur_params_u_}, blur_params);
    ::bgfx::setTexture(0, ::bgfx::UniformHandle{s_ssao_input_u_}, ::bgfx::TextureHandle{ssao_raw_tex_});
    ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{fullscreen_vb_});
    ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{fullscreen_ib_});
    ::bgfx::setState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A);
    ::bgfx::submit(kSsaoBlurView, ::bgfx::ProgramHandle{ssao_blur_program_});

    return KE_OK;
}

ke_result BgfxRenderSystem::SetSsao(bool enabled, float radius, float bias, float strength)
{
    ssao_enabled_  = enabled;
    ssao_radius_   = radius;
    ssao_bias_     = bias;
    ssao_strength_ = strength;
    return KE_OK;
}

ke_result BgfxRenderSystem::SetupClustered()
{
    auto load_shader = [&](const char *name) -> ::bgfx::ShaderHandle {
        std::string path = shader_path_ + "/" + name + ".bin";
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open()) return ::bgfx::ShaderHandle{::bgfx::kInvalidHandle};
        auto size = (uint32_t)file.tellg();
        file.seekg(0);
        const ::bgfx::Memory *mem = ::bgfx::alloc(size);
        file.read(reinterpret_cast<char *>(mem->data), size);
        return ::bgfx::createShader(mem);
    };

    ::bgfx::ShaderHandle vs_d = load_shader("vs_depth");
    ::bgfx::ShaderHandle fs_d = load_shader("fs_depth");
    if (::bgfx::isValid(vs_d) && ::bgfx::isValid(fs_d))
        depth_program_ = ::bgfx::createProgram(vs_d, fs_d, true).idx;

    ::bgfx::ShaderHandle cs_c = load_shader("cs_light_cull");
    if (::bgfx::isValid(cs_c))
        cull_program_ = ::bgfx::createProgram(cs_c, true).idx;

    cluster_params_u_  = ::bgfx::createUniform("u_clusterParams",  ::bgfx::UniformType::Vec4).idx;
    cluster_params2_u_ = ::bgfx::createUniform("u_clusterParams2", ::bgfx::UniformType::Vec4).idx;
    compute_view_u_    = ::bgfx::createUniform("u_computeView",    ::bgfx::UniformType::Mat4).idx;

    RebuildClusterBuffers();
    return KE_OK;
}

void BgfxRenderSystem::RebuildClusterBuffers()
{
    auto destroy_buffer = [](uint16_t &h) {
        if (::bgfx::isValid(::bgfx::DynamicIndexBufferHandle{h})) ::bgfx::destroy(::bgfx::DynamicIndexBufferHandle{h});
        h = kInvalidHandle;
    };

    destroy_buffer(b_cluster_bounds_);
    destroy_buffer(b_point_lights_);
    destroy_buffer(b_spot_lights_);
    destroy_buffer(b_p_light_indices_);
    destroy_buffer(b_p_light_count_);
    destroy_buffer(b_s_light_indices_);
    destroy_buffer(b_s_light_count_);

    uint32_t numClusters = cluster_config_.grid_x * cluster_config_.grid_y * cluster_config_.grid_z;

    // ClusterBounds: AABB (min vec4, max vec4) = 32 bytes
    b_cluster_bounds_ = ::bgfx::createDynamicIndexBuffer(numClusters * 32 / 2, BGFX_BUFFER_COMPUTE_READ).idx;

    // Light storage: PointLight=32b, SpotLight=48b
    b_point_lights_ = ::bgfx::createDynamicIndexBuffer(cluster_config_.max_total_lights * 32 / 2, BGFX_BUFFER_COMPUTE_READ).idx;
    b_spot_lights_  = ::bgfx::createDynamicIndexBuffer(cluster_config_.max_total_lights * 48 / 2, BGFX_BUFFER_COMPUTE_READ).idx;

    // Light lists: uint32 per slot
    b_p_light_indices_ = ::bgfx::createDynamicIndexBuffer(numClusters * cluster_config_.max_lights_per_cluster * 4 / 2, BGFX_BUFFER_COMPUTE_READ_WRITE).idx;
    b_s_light_indices_ = ::bgfx::createDynamicIndexBuffer(numClusters * cluster_config_.max_lights_per_cluster * 4 / 2, BGFX_BUFFER_COMPUTE_READ_WRITE).idx;

    // Light counts: uint32 per cluster
    b_p_light_count_ = ::bgfx::createDynamicIndexBuffer(numClusters * 4 / 2, BGFX_BUFFER_COMPUTE_READ_WRITE).idx;
    b_s_light_count_ = ::bgfx::createDynamicIndexBuffer(numClusters * 4 / 2, BGFX_BUFFER_COMPUTE_READ_WRITE).idx;

    bounds_dirty_ = true;
}

void BgfxRenderSystem::UpdateClusterBounds()
{
    if (!bounds_dirty_) return;

    float nearZ = near_z_;
    float farZ  = far_z_;

    uint32_t numX = cluster_config_.grid_x;
    uint32_t numY = cluster_config_.grid_y;
    uint32_t numZ = cluster_config_.grid_z;

    struct AABB { float min[4]; float max[4]; };
    std::vector<AABB> bounds(numX * numY * numZ);

    // Invert projection to get view-space coords from NDC.
    // Column-major: m[0]=1/tan(fovX/2), m[5]=1/tan(fovY/2).
    float invProj00 = 1.0f / last_proj_[0];
    float invProj11 = 1.0f / last_proj_[5];

    for (uint32_t iz = 0; iz < numZ; ++iz)
    {
        float z0 = nearZ * powf(farZ / nearZ, (float)iz / numZ);
        float z1 = nearZ * powf(farZ / nearZ, (float)(iz + 1) / numZ);

        for (uint32_t iy = 0; iy < numY; ++iy)
        {
            float yNDC0 = (float)iy / numY * 2.0f - 1.0f;
            float yNDC1 = (float)(iy + 1) / numY * 2.0f - 1.0f;

            for (uint32_t ix = 0; ix < numX; ++ix)
            {
                float xNDC0 = (float)ix / numX * 2.0f - 1.0f;
                float xNDC1 = (float)(ix + 1) / numX * 2.0f - 1.0f;

                // Points at z0 and z1 in view space
                // View space: -Z is forward. Cluster Z is positive forward.
                float vz0 = -z0;
                float vz1 = -z1;

                float x0z0 = xNDC0 * z0 * invProj00;
                float x1z0 = xNDC1 * z0 * invProj00;
                float y0z0 = yNDC0 * z0 * invProj11;
                float y1z0 = yNDC1 * z0 * invProj11;

                float x0z1 = xNDC0 * z1 * invProj00;
                float x1z1 = xNDC1 * z1 * invProj00;
                float y0z1 = yNDC0 * z1 * invProj11;
                float y1z1 = yNDC1 * z1 * invProj11;

                AABB &b = bounds[iz * numX * numY + iy * numX + ix];
                b.min[0] = std::min({x0z0, x1z0, x0z1, x1z1});
                b.min[1] = std::min({y0z0, y1z0, y0z1, y1z1});
                b.min[2] = vz1; // -farZ_cluster is more negative
                b.min[3] = 0.0f;

                b.max[0] = std::max({x0z0, x1z0, x0z1, x1z1});
                b.max[1] = std::max({y0z0, y1z0, y0z1, y1z1});
                b.max[2] = vz0; // -nearZ_cluster
                b.max[3] = 0.0f;
            }
        }
    }

    ::bgfx::update(::bgfx::DynamicIndexBufferHandle{b_cluster_bounds_}, 0,
                   ::bgfx::copy(bounds.data(), (uint32_t)(bounds.size() * sizeof(AABB))));
    bounds_dirty_ = false;
}

void BgfxRenderSystem::DispatchLightCull()
{
    if (cull_program_ == kInvalidHandle) return;

    // View-space transformation for light positions
    ::bgfx::setUniform(::bgfx::UniformHandle{compute_view_u_}, last_view_);

    float params[4] = {(float)cluster_config_.grid_x, (float)cluster_config_.grid_y,
                       (float)cluster_config_.grid_z, (float)cluster_config_.max_lights_per_cluster};
    ::bgfx::setUniform(::bgfx::UniformHandle{cluster_params_u_}, params);

    float params2[4] = {(float)point_lights_.size(), (float)spot_lights_.size(), 0.f, 0.f};
    ::bgfx::setUniform(::bgfx::UniformHandle{cluster_params2_u_}, params2);

    ::bgfx::setBuffer(0, ::bgfx::DynamicIndexBufferHandle{b_cluster_bounds_}, ::bgfx::Access::Read);
    ::bgfx::setBuffer(1, ::bgfx::DynamicIndexBufferHandle{b_point_lights_},   ::bgfx::Access::Read);
    ::bgfx::setBuffer(2, ::bgfx::DynamicIndexBufferHandle{b_spot_lights_},    ::bgfx::Access::Read);

    ::bgfx::setBuffer(3, ::bgfx::DynamicIndexBufferHandle{b_p_light_indices_}, ::bgfx::Access::ReadWrite);
    ::bgfx::setBuffer(4, ::bgfx::DynamicIndexBufferHandle{b_p_light_count_},   ::bgfx::Access::ReadWrite);
    ::bgfx::setBuffer(5, ::bgfx::DynamicIndexBufferHandle{b_s_light_indices_}, ::bgfx::Access::ReadWrite);
    ::bgfx::setBuffer(6, ::bgfx::DynamicIndexBufferHandle{b_s_light_count_},   ::bgfx::Access::ReadWrite);

    ::bgfx::dispatch(kLightCullView, ::bgfx::ProgramHandle{cull_program_},
                     (uint16_t)cluster_config_.grid_x, (uint16_t)cluster_config_.grid_y, (uint16_t)cluster_config_.grid_z);
}

ke_result BgfxRenderSystem::SetClusterConfig(const ke_cluster_config *config)
{
    if (!config) return KE_ERROR_INVALID_ARGUMENT;
    if (config->grid_x == 0 || config->grid_y == 0 || config->grid_z == 0) return KE_ERROR_INVALID_ARGUMENT;
    cluster_config_ = *config;
    RebuildClusterBuffers();
    return KE_OK;
}

} // namespace kernel_engine::render::bgfx

extern "C" {
    ke_result ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_render **out_render) {
        if (!out_render || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;
        void *mem = params->allocator->alloc(params->allocator, sizeof(kernel_engine::render::bgfx::BgfxRenderSystem), 0);
        auto *sys = new (mem) kernel_engine::render::bgfx::BgfxRenderSystem(params);
        *out_render = sys->ToApi();
        return KE_OK;
    }
}
