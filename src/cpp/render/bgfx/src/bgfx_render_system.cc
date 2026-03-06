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

    ::bgfx::setViewClear(0, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 0x303030ff, 1.0f, 0);
    ::bgfx::setViewRect(0, 0, 0, (uint16_t)w, (uint16_t)h);

    ::bgfx::setViewClear(1, BGFX_CLEAR_NONE);
    ::bgfx::setViewRect(1, 0, 0, (uint16_t)w, (uint16_t)h);

    return SetupShader();
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

    static const ke_vertex kVerts[4] = {
        {-0.5f, -0.5f, 0.0f,  0.0f, 0.0f, 1.0f,  0.0f, 0.0f},
        { 0.5f, -0.5f, 0.0f,  0.0f, 0.0f, 1.0f,  1.0f, 0.0f},
        { 0.5f,  0.5f, 0.0f,  0.0f, 0.0f, 1.0f,  1.0f, 1.0f},
        {-0.5f,  0.5f, 0.0f,  0.0f, 0.0f, 1.0f,  0.0f, 1.0f},
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
    skybox_sampler_uniform_ = ::bgfx::createUniform("s_skybox",       ::bgfx::UniformType::Sampler).idx;
    skybox_tint_uniform_    = ::bgfx::createUniform("u_skyboxTint",   ::bgfx::UniformType::Vec4).idx;

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
    ::bgfx::setViewTransform(0, view->m, proj->m);
    return KE_OK;
}

ke_result BgfxRenderSystem::Frame()
{
    ::bgfx::touch(0);
    ::bgfx::touch(1);
    ::bgfx::frame();
    has_skybox_     = false;
    active_env_tex_ = kInvalidHandle;
    return KE_OK;
}

ke_result BgfxRenderSystem::ClearColor(float r, float g, float b, float a)
{
    uint32_t color = (uint32_t(r * 255.0F) << 24) | (uint32_t(g * 255.0F) << 16) |
                     (uint32_t(b * 255.0F) << 8)  | (uint32_t(a * 255.0F));
    ::bgfx::setViewClear(0, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, color, 1.0f, 0);
    return KE_OK;
}

ke_result BgfxRenderSystem::CreateMesh(const ke_vertex *verts, uint32_t vert_count,
                                        const uint16_t *indices, uint32_t index_count,
                                        ke_mesh_handle *out_handle)
{
    if (!verts || !indices || !out_handle || vert_count == 0 || index_count == 0) return KE_ERROR_INVALID_ARGUMENT;

    struct GpuVert { float x, y, z; uint32_t abgr; float nx, ny, nz; float u, v; };
    std::vector<GpuVert> expanded(vert_count);
    for (uint32_t i = 0; i < vert_count; i++)
        expanded[i] = {verts[i].x, verts[i].y, verts[i].z, 0xffffffff,
                       verts[i].nx, verts[i].ny, verts[i].nz,
                       verts[i].u, verts[i].v};

    ::bgfx::VertexLayout layout;
    layout.begin()
        .add(::bgfx::Attrib::Position,  3, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::Color0,    4, ::bgfx::AttribType::Uint8,  true)
        .add(::bgfx::Attrib::Normal,    3, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::TexCoord0, 2, ::bgfx::AttribType::Float)
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

ke_result BgfxRenderSystem::CreateTextureRgba(uint32_t width, uint32_t height,
                                               const uint8_t *pixels,
                                               ke_texture_handle *out_handle)
{
    if (!pixels || !out_handle || width == 0 || height == 0) return KE_ERROR_INVALID_ARGUMENT;
    uint16_t idx = ::bgfx::createTexture2D(
        (uint16_t)width, (uint16_t)height, false, 1,
        ::bgfx::TextureFormat::RGBA8, 0,
        ::bgfx::copy(pixels, width * height * 4)).idx;
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
    uint32_t total = 6u * size * size * 4u;
    uint16_t idx = ::bgfx::createTextureCube(
        (uint16_t)size, false, 1,
        ::bgfx::TextureFormat::RGBA8, 0,
        ::bgfx::copy(data, total)).idx;
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
    ::bgfx::setViewTransform(1, rotView, last_proj_);

    float tint[4] = {1.f, 1.f, 1.f, 1.f};
    ::bgfx::setUniform(::bgfx::UniformHandle{skybox_tint_uniform_}, tint);
    ::bgfx::setTexture(0, ::bgfx::UniformHandle{skybox_sampler_uniform_}, ::bgfx::TextureHandle{tex.idx});
    ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{skybox_vb_});
    ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{skybox_ib_});
    ::bgfx::setState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A | BGFX_STATE_DEPTH_TEST_LEQUAL);
    ::bgfx::submit(1, ::bgfx::ProgramHandle{skybox_program_});

    has_skybox_     = true;
    active_env_tex_ = tex.idx;
    return KE_OK;
}

ke_result BgfxRenderSystem::CreateMaterial(const ke_material *mat, ke_material_handle *out_handle)
{
    if (!mat || !out_handle) return KE_ERROR_INVALID_ARGUMENT;
    uint32_t tex = (mat->albedo < (ke_texture_handle)textures_.size()) ? mat->albedo : 0;
    materials_.push_back({mat->r, mat->g, mat->b, mat->a, tex, mat->metallic, mat->roughness, true});
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
    float color[4]     = {mat.r, mat.g, mat.b, mat.a};
    float pbr_params[4]= {mat.metallic, mat.roughness, 0.f, 0.f};

    ::bgfx::setUniform(::bgfx::UniformHandle{color_uniform_},         color);
    ::bgfx::setUniform(::bgfx::UniformHandle{light_dir_uniform_},     light_dir_);
    ::bgfx::setUniform(::bgfx::UniformHandle{light_color_uniform_},   light_color_);
    ::bgfx::setUniform(::bgfx::UniformHandle{ambient_color_uniform_}, ambient_color_);
    ::bgfx::setUniform(::bgfx::UniformHandle{pbr_params_uniform_},    pbr_params);
    ::bgfx::setUniform(::bgfx::UniformHandle{camera_pos_uniform_},    camera_pos_);

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

    ::bgfx::setTexture(0, ::bgfx::UniformHandle{sampler_uniform_}, ::bgfx::TextureHandle{textures_[tex_idx].idx});
    ::bgfx::setVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
    ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
    ::bgfx::setTransform(transform->m);
    ::bgfx::setState(BGFX_STATE_DEFAULT);
    ::bgfx::submit(0, ::bgfx::ProgramHandle{program_});
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
