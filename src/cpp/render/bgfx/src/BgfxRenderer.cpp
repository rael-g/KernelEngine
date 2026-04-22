#include "BgfxRenderer.hpp"
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/window/window.h>
#include "bgfx_interface.hh"
#include <bgfx/bgfx.h>
#include <bgfx/platform.h>
#include <new>
#include <cstring>
#include <fstream>
#include <cmath>
#include <stdarg.h>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

static ke_result LogErr(ke_logger *logger, ke_result r, const char *context, const char *detail)
{
    if (logger)
    {
        char msg[1024];
        snprintf(msg, sizeof(msg), "%s: %s (result: %d)", context, detail, r);
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "bgfx", msg};
        logger->log(logger, &ev);
    }
    return r;
}

// ── BgfxLogCallback Implementation ────────────────────────────────────────

void BgfxLogCallback::fatal(const char *_filePath, uint16_t _line, ::bgfx::Fatal::Enum _code, const char *_str)
{
    if (logger_)
    {
        char msg[1024];
        snprintf(msg, sizeof(msg), "FATAL 0x%08x at %s:%d: %s", _code, _filePath, _line, _str);
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "bgfx", msg};
        logger_->log(logger_, &ev);
    }
    abort();
}

void BgfxLogCallback::traceVargs(const char *_filePath, uint16_t _line, const char *_format, va_list _argList)
{
    if (logger_)
    {
        char msg[1024];
        vsnprintf(msg, sizeof(msg), _format, _argList);
        ke_log_event ev = {KE_LOG_LEVEL_TRACE, "bgfx", msg};
        logger_->log(logger_, &ev);
    }
}

// ── BgfxRenderer Implementation ───────────────────────────────────────────

BgfxRenderer::BgfxRenderer(const ke_render_bgfx_params *params)
    : allocator_(params->allocator), logger_(params->logger), window_(params->window),
      shader_path_((params->shader_path != nullptr) ? params->shader_path : "")
{
    std::memset(&render_api_, 0, sizeof(render_api_));
    std::memset(last_view_, 0, sizeof(last_view_));
    std::memset(last_proj_ , 0, sizeof(last_proj_));
    std::memset(active_light_vp_, 0, sizeof(active_light_vp_));

    void* backend_mem = allocator_->alloc(allocator_, sizeof(RealBgfxBackend), alignof(RealBgfxBackend));
    bgfx_ = new (backend_mem) RealBgfxBackend();
    own_bgfx_ = true;

    callback_.SetLogger(logger_);
    render_api_.handle = this;
    
    // Wire up the C API dispatchers
    render_api_.on_initialize = [](ke_render *self) { return static_cast<BgfxRenderer *>(self->handle)->OnInitialize(); };
    render_api_.on_shutdown = [](ke_render *self) { return static_cast<BgfxRenderer *>(self->handle)->OnShutdown(); };
    render_api_.destroy = [](ke_render *self) {
        if (!self) return;
        auto *sys = static_cast<BgfxRenderer *>(self->handle);
        auto *alloc = sys->allocator_;
        sys->~BgfxRenderer();
        alloc->free(alloc, sys);
    };
    render_api_.frame = [](ke_render *self) { return static_cast<BgfxRenderer *>(self->handle)->Frame(); };
    render_api_.clear_color = [](ke_render *self, float r, float g, float b, float a) {
        return static_cast<BgfxRenderer *>(self->handle)->ClearColor(r, g, b, a);
    };
    render_api_.set_orthographic = [](ke_render *self, ke_bool enabled) {
        return static_cast<BgfxRenderer *>(self->handle)->SetOrthographic(enabled);
    };
    render_api_.set_view_transform = [](ke_render *self, const ke_mat4 *view, const ke_mat4 *proj) {
        return static_cast<BgfxRenderer *>(self->handle)->SetViewTransform(view, proj);
    };
    render_api_.create_texture_rgba = [](ke_render *self, uint32_t w, uint32_t h, const uint8_t *px, ke_texture_handle *out) {
        return static_cast<BgfxRenderer *>(self->handle)->CreateTextureRgba(w, h, px, out);
    };
    render_api_.destroy_texture = [](ke_render *self, ke_texture_handle handle) {
        return static_cast<BgfxRenderer *>(self->handle)->DestroyTexture(handle);
    };
    render_api_.create_mesh = [](ke_render *self, const ke_vertex *v, uint32_t vc, const uint16_t *i, uint32_t ic, ke_mesh_handle *out) {
        return static_cast<BgfxRenderer *>(self->handle)->CreateMesh(v, vc, i, ic, out);
    };
    render_api_.destroy_mesh = [](ke_render *self, ke_mesh_handle h) {
        return static_cast<BgfxRenderer *>(self->handle)->DestroyMesh(h);
    };
    render_api_.submit_mesh = [](ke_render *self, ke_mesh_handle m, ke_material_handle mat, const ke_mat4 *t) {
        return static_cast<BgfxRenderer *>(self->handle)->SubmitMesh(m, mat, t);
    };
    render_api_.create_cubemap_rgba = [](ke_render *self, uint32_t s, const uint8_t *d, ke_texture_handle *out) {
        return static_cast<BgfxRenderer *>(self->handle)->CreateCubemapRgba(s, d, out);
    };
    render_api_.submit_skybox = [](ke_render *self, ke_texture_handle h) {
        return static_cast<BgfxRenderer *>(self->handle)->SubmitSkybox(h);
    };
    render_api_.set_tonemapping = [](ke_render *self, ke_bool e, float ex, float g) {
        return static_cast<BgfxRenderer *>(self->handle)->SetTonemapping(e, ex, g);
    };
    render_api_.set_bloom = [](ke_render *self, ke_bool e, float t, float i) {
        return static_cast<BgfxRenderer *>(self->handle)->SetBloom(e, t, i);
    };
    render_api_.create_shadow_map = [](ke_render *self, uint32_t w, uint32_t h, ke_shadow_map_handle *out) {
        return static_cast<BgfxRenderer *>(self->handle)->CreateShadowMap(w, h, out);
    };
    render_api_.destroy_shadow_map = [](ke_render *self, ke_shadow_map_handle h) {
        return static_cast<BgfxRenderer *>(self->handle)->DestroyShadowMap(h);
    };
    render_api_.begin_shadow_pass = [](ke_render *self, ke_shadow_map_handle h, const ke_mat4 *v, const ke_mat4 *p) {
        return static_cast<BgfxRenderer *>(self->handle)->BeginShadowPass(h, v, p);
    };
    render_api_.submit_mesh_shadow = [](ke_render *self, ke_mesh_handle m, const ke_mat4 *t) {
        return static_cast<BgfxRenderer *>(self->handle)->SubmitMeshShadow(m, t);
    };
    render_api_.end_shadow_pass = [](ke_render *self) {
        return static_cast<BgfxRenderer *>(self->handle)->EndShadowPass();
    };
    render_api_.set_shadow_map = [](ke_render *self, ke_shadow_map_handle h) {
        return static_cast<BgfxRenderer *>(self->handle)->SetShadowMap(h);
    };
    render_api_.create_material = [](ke_render *self, const ke_material *m, ke_material_handle *out) {
        return static_cast<BgfxRenderer *>(self->handle)->CreateMaterial(m, out);
    };
    render_api_.destroy_material = [](ke_render *self, ke_material_handle h) {
        return static_cast<BgfxRenderer *>(self->handle)->DestroyMaterial(h);
    };
    render_api_.set_directional_light = [](ke_render *self, const ke_directional_light *l) {
        return static_cast<BgfxRenderer *>(self->handle)->SetDirectionalLight(l);
    };
    render_api_.set_ambient_light = [](ke_render *self, float r, float g, float b) {
        return static_cast<BgfxRenderer *>(self->handle)->SetAmbientLight(r, g, b);
    };
    render_api_.set_point_lights = [](ke_render *self, const ke_point_light *ls, uint32_t c) {
        return static_cast<BgfxRenderer *>(self->handle)->SetPointLights(ls, c);
    };
    render_api_.set_spot_lights = [](ke_render *self, const ke_spot_light *ls, uint32_t c) {
        return static_cast<BgfxRenderer *>(self->handle)->SetSpotLights(ls, c);
    };
    render_api_.set_camera_pos = [](ke_render *self, float x, float y, float z) {
        return static_cast<BgfxRenderer *>(self->handle)->SetCameraPos(x, y, z);
    };
    render_api_.set_ssao = [](ke_render *self, ke_bool e, float r, float b, float s) {
        return static_cast<BgfxRenderer *>(self->handle)->SetSsao(e, r, b, s);
    };
    render_api_.set_cluster_config = [](ke_render *self, const ke_cluster_config *cfg) {
        return static_cast<BgfxRenderer *>(self->handle)->SetClusterConfig(cfg);
    };
}

BgfxRenderer::~BgfxRenderer()
{
    if (own_bgfx_ && bgfx_)
    {
        bgfx_->~BgfxBackend();
        allocator_->free(allocator_, bgfx_);
    }
}

ke_result BgfxRenderer::OnInitialize()
{
    if (!window_) return KE_ERROR_NOT_INITIALIZED;
    void *nwh = window_->get_native_handle(window_);
    if (!nwh) return KE_ERROR_WINDOW;

    ::bgfx::Init init;
    init.type = ::bgfx::RendererType::Vulkan;
    init.platformData.nwh = nwh;
    init.callback = &callback_;

#ifndef NDEBUG
    init.debug = true;
#endif

    int32_t w, h;
    window_->get_size(window_, &w, &h);
    init.resolution.width  = (uint32_t)w;
    init.resolution.height = (uint32_t)h;
    init.resolution.reset  = BGFX_RESET_VSYNC;

    if (!bgfx_->Init(init))
    {
        return LogErr(logger_, KE_ERROR_RENDER, "OnInitialize", "bgfx::init() failed");
    }

    view_w_ = w;
    view_h_ = h;

    bgfx_->SetViewClear(kDepthView, BGFX_CLEAR_DEPTH, 0, 1.0f, 0);
    bgfx_->SetViewRect(kDepthView, 0, 0, (uint16_t)w, (uint16_t)h);

    bgfx_->SetViewClear(kSceneView, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 0x303030ff, 1.0f, 0);
    bgfx_->SetViewRect(kSceneView, 0, 0, (uint16_t)w, (uint16_t)h);
    bgfx_->SetViewMode(kSceneView, ::bgfx::ViewMode::Sequential);

    ke_result res = SetupShader();
    if (res != KE_OK) return res;
    res = SetupPostProcess();
    if (res != KE_OK) return res;
    res = SetupSsao();
    if (res != KE_OK) return res;
    res = SetupClustered();
    if (res != KE_OK) return res;

    initialized_ = true;
    return KE_OK;
}

ke_result BgfxRenderer::OnShutdown()
{
    for (auto &t : textures_)
        if (::bgfx::isValid(::bgfx::TextureHandle{t.idx})) bgfx_->Destroy(::bgfx::TextureHandle{t.idx});
    textures_.clear();

    for (auto &entry : meshes_)
    {
        if (::bgfx::isValid(::bgfx::IndexBufferHandle{entry.ib}))  bgfx_->Destroy(::bgfx::IndexBufferHandle{entry.ib});
        if (::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb})) bgfx_->Destroy(::bgfx::VertexBufferHandle{entry.vb});
    }
    meshes_.clear();

    if (::bgfx::isValid(::bgfx::VertexBufferHandle{skybox_vb_}))  bgfx_->Destroy(::bgfx::VertexBufferHandle{skybox_vb_});
    if (::bgfx::isValid(::bgfx::IndexBufferHandle{skybox_ib_}))   bgfx_->Destroy(::bgfx::IndexBufferHandle{skybox_ib_});
    if (::bgfx::isValid(::bgfx::TextureHandle{default_cube_tex_})) bgfx_->Destroy(::bgfx::TextureHandle{default_cube_tex_});

    auto destroy_uniform = [this](uint16_t u) {
        if (::bgfx::isValid(::bgfx::UniformHandle{u})) bgfx_->Destroy(::bgfx::UniformHandle{u});
    };
    auto destroy_fb = [this](uint16_t h) {
        if (::bgfx::isValid(::bgfx::FrameBufferHandle{h})) bgfx_->Destroy(::bgfx::FrameBufferHandle{h});
    };
    auto destroy_tex = [this](uint16_t h) {
        if (::bgfx::isValid(::bgfx::TextureHandle{h})) bgfx_->Destroy(::bgfx::TextureHandle{h});
    };

    destroy_uniform(tonemap_params_uniform_);
    destroy_uniform(blur_params_uniform_);
    destroy_uniform(bloom_params_uniform_);
    destroy_uniform(blur_tex_uniform_);
    destroy_uniform(bloom_tex_uniform_);
    destroy_uniform(hdr_tex_uniform_);

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
    if (::bgfx::isValid(::bgfx::ProgramHandle{ssao_blur_program_})) bgfx_->Destroy(::bgfx::ProgramHandle{ssao_blur_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{ssao_program_}))      bgfx_->Destroy(::bgfx::ProgramHandle{ssao_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{prepass_program_}))   bgfx_->Destroy(::bgfx::ProgramHandle{prepass_program_});

    destroy_fb(blur_b_fb_);
    destroy_fb(blur_a_fb_);
    destroy_fb(bright_fb_);
    destroy_fb(hdr_fb_);
    if (::bgfx::isValid(::bgfx::TextureHandle{hdr_color_tex_})) bgfx_->Destroy(::bgfx::TextureHandle{hdr_color_tex_});
    if (::bgfx::isValid(::bgfx::IndexBufferHandle{fullscreen_ib_}))  bgfx_->Destroy(::bgfx::IndexBufferHandle{fullscreen_ib_});
    if (::bgfx::isValid(::bgfx::VertexBufferHandle{fullscreen_vb_})) bgfx_->Destroy(::bgfx::VertexBufferHandle{fullscreen_vb_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{tonemap_program_}))     bgfx_->Destroy(::bgfx::ProgramHandle{tonemap_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{blur_program_}))        bgfx_->Destroy(::bgfx::ProgramHandle{blur_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{bright_pass_program_})) bgfx_->Destroy(::bgfx::ProgramHandle{bright_pass_program_});

    destroy_uniform(cluster_params_u_);
    destroy_uniform(cluster_params2_u_);
    destroy_uniform(compute_view_u_);
    if (::bgfx::isValid(::bgfx::ProgramHandle{depth_program_})) bgfx_->Destroy(::bgfx::ProgramHandle{depth_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{cull_program_}))  bgfx_->Destroy(::bgfx::ProgramHandle{cull_program_});

    auto destroy_dyn_ib = [this](uint16_t h) {
        if (::bgfx::isValid(::bgfx::DynamicIndexBufferHandle{h})) bgfx_->Destroy(::bgfx::DynamicIndexBufferHandle{h});
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
        if (::bgfx::isValid(::bgfx::FrameBufferHandle{sm.fb}))   bgfx_->Destroy(::bgfx::FrameBufferHandle{sm.fb});
        if (::bgfx::isValid(::bgfx::TextureHandle{sm.depth_tex})) bgfx_->Destroy(::bgfx::TextureHandle{sm.depth_tex});
        if (::bgfx::isValid(::bgfx::TextureHandle{sm.color_tex})) bgfx_->Destroy(::bgfx::TextureHandle{sm.color_tex});
    }
    shadow_maps_.clear();

    if (::bgfx::isValid(::bgfx::ProgramHandle{shadow_program_})) bgfx_->Destroy(::bgfx::ProgramHandle{shadow_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{skybox_program_})) bgfx_->Destroy(::bgfx::ProgramHandle{skybox_program_});
    if (::bgfx::isValid(::bgfx::ProgramHandle{program_}))         bgfx_->Destroy(::bgfx::ProgramHandle{program_});

    bgfx_->Shutdown();
    initialized_ = false;
    return KE_OK;
}

ke_result BgfxRenderer::Frame()
{
    if (!initialized_) return KE_ERROR_NOT_INITIALIZED;
    UpdateClusterBounds();
    DispatchLightCull();

    if (ssao_enabled_ && gbuf_fb_ != kInvalidHandle)
    {
        bgfx_->SetViewFrameBuffer(kPrepassView,  ::bgfx::FrameBufferHandle{gbuf_fb_});
        bgfx_->SetViewClear(kPrepassView, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 0x00000000, 1.0f, 0);
        bgfx_->SetViewRect(kPrepassView,  0, 0, (uint16_t)view_w_, (uint16_t)view_h_);

        bgfx_->SetViewFrameBuffer(kSsaoView, ::bgfx::FrameBufferHandle{ssao_raw_fb_});
        bgfx_->SetViewClear(kSsaoView, BGFX_CLEAR_COLOR, 0xffffffff, 1.0f, 0);
        bgfx_->SetViewRect(kSsaoView, 0, 0, (uint16_t)view_w_, (uint16_t)view_h_);

        bgfx_->SetViewFrameBuffer(kSsaoBlurView, ::bgfx::FrameBufferHandle{ssao_blur_fb_});
        bgfx_->SetViewClear(kSsaoBlurView, BGFX_CLEAR_COLOR, 0xffffffff, 1.0f, 0);
        bgfx_->SetViewRect(kSsaoBlurView, 0, 0, (uint16_t)view_w_, (uint16_t)view_h_);

        SubmitSsao();
    }

    if (pp_enabled_ && hdr_fb_ != kInvalidHandle)
    {
        bgfx_->SetViewFrameBuffer(kSceneView, ::bgfx::FrameBufferHandle{hdr_fb_});
        SubmitPostProcess();
    }
    else
    {
        bgfx_->SetViewFrameBuffer(kSceneView, ::bgfx::FrameBufferHandle{::bgfx::kInvalidHandle});
    }

    bgfx_->Touch(kSceneView);
    bgfx_->Frame();
    
    has_skybox_           = false;
    active_env_tex_       = kInvalidHandle;
    active_shadow_handle_ = kInvalidShadowHandle;
    point_lights_.clear();
    spot_lights_.clear();
    return KE_OK;
}

ke_result BgfxRenderer::SetOrthographic(ke_bool enabled) {
    orthographic_ = (enabled != 0);
    return KE_OK;
}

ke_result BgfxRenderer::ClearColor(float r, float g, float b, float a)
{
    if (!initialized_) return KE_ERROR_NOT_INITIALIZED;
    uint32_t color = (uint32_t(r * 255.0F) << 24) | (uint32_t(g * 255.0F) << 16) |
                     (uint32_t(b * 255.0F) << 8)  | (uint32_t(a * 255.0F));
    bgfx_->SetViewClear(kSceneView, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, color, 1.0f, 0);
    return KE_OK;
}

ke_result BgfxRenderer::SetViewTransform(const ke_mat4 *view, const ke_mat4 *proj)
{
    if (!view || !proj) return KE_ERROR_INVALID_ARGUMENT;
    std::memcpy(last_view_, view->m, sizeof(float) * 16);
    std::memcpy(last_proj_, proj->m, sizeof(float) * 16);

    // Default near/far if math fails
    float n = 0.1f;
    float f = 1000.0f;

    // Basic extraction from standard projection matrix
    if (std::abs(proj->m[10] - proj->m[11]) > 0.0001f) {
        n = proj->m[14] / (proj->m[10] + 1.0f);
        f = proj->m[14] / (proj->m[10] - 1.0f);
    }
    
    if (std::abs(n - near_z_) > 0.0001f || std::abs(f - far_z_) > 0.0001f) {
        near_z_ = n;
        far_z_  = f;
        bounds_dirty_ = true;
    }

    ssao_proj_info_[0] = (proj->m[0] != 0.f) ? (1.0f / proj->m[0]) : 1.0f;
    ssao_proj_info_[1] = (proj->m[5] != 0.f) ? (1.0f / proj->m[5]) : 1.0f;
    
    bgfx_->SetViewTransform(kDepthView,   view->m, proj->m);
    bgfx_->SetViewTransform(kPrepassView, view->m, proj->m);
    bgfx_->SetViewTransform(kSsaoView,    view->m, proj->m);
    bgfx_->SetViewTransform(kSceneView,   view->m, proj->m);
    return KE_OK;
}

ke_result BgfxRenderer::SetCameraPos(float x, float y, float z)
{
    camera_pos_[0] = x; camera_pos_[1] = y; camera_pos_[2] = z; camera_pos_[3] = 0.f;
    return KE_OK;
}

::bgfx::ShaderHandle BgfxRenderer::LoadShader(const char *name)
{
    std::string path = shader_path_ + "/" + name + ".bin";
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) return ::bgfx::ShaderHandle{::bgfx::kInvalidHandle};
    auto size = (uint32_t)file.tellg();
    file.seekg(0);
    const ::bgfx::Memory *mem = bgfx_->Alloc(size + 1);
    file.read(reinterpret_cast<char *>(mem->data), size);
    mem->data[size] = '\0';
    return bgfx_->CreateShader(mem);
}

ke_result BgfxRenderer::SetupShader()
{
    ::bgfx::ShaderHandle vs = LoadShader("vs_basic");
    ::bgfx::ShaderHandle fs = LoadShader("fs_basic");
    if (!::bgfx::isValid(vs) || !::bgfx::isValid(fs)) return KE_ERROR_RENDER;
    
    ::bgfx::ProgramHandle prog = bgfx_->CreateProgram(vs, fs, true);
    if (!::bgfx::isValid(prog)) return KE_ERROR_RENDER;
    program_ = prog.idx;

    // Default white texture
    uint32_t white = 0xffffffff;
    ke_texture_handle white_handle;
    if (CreateTextureRgba(1, 1, reinterpret_cast<const uint8_t *>(&white), &white_handle) != KE_OK)
        return KE_ERROR_RENDER;
    textures_[0].idx = textures_[white_handle].idx;

    // Default white cubemap
    {
        static const uint8_t kWhiteFace[4] = {0xff, 0xff, 0xff, 0xff};
        const ::bgfx::Memory *mem = bgfx_->Alloc(6 * 4);
        for (int f = 0; f < 6; ++f) std::memcpy(mem->data + f * 4, kWhiteFace, 4);
        ::bgfx::TextureHandle h = bgfx_->CreateTextureCube(1, false, 1, ::bgfx::TextureFormat::RGBA8, 0, mem);
        default_cube_tex_ = ::bgfx::isValid(h) ? h.idx : kInvalidHandle;
    }

    // Load extra programs
    auto load_extra = [&](const char* vs_n, const char* fs_n, uint16_t& out_p) {
        auto v = LoadShader(vs_n);
        auto f = LoadShader(fs_n);
        if (::bgfx::isValid(v) && ::bgfx::isValid(f)) {
            auto p = bgfx_->CreateProgram(v, f, true);
            if (::bgfx::isValid(p)) out_p = p.idx;
        }
    };

    load_extra("vs_shadow", "fs_shadow", shadow_program_);
    load_extra("vs_skybox", "fs_skybox", skybox_program_);

    // Internal primitives
    struct SkyVert { float x, y, z; };
    static const SkyVert kSkyVerts[8] = {{-1,-1,-1}, {1,-1,-1}, {1,1,-1}, {-1,1,-1}, {-1,-1,1}, {1,-1,1}, {1,1,1}, {-1,1,1}};
    static const uint16_t kSkyIdx[36] = {0,1,2, 0,2,3, 5,4,7, 5,7,6, 4,0,3, 4,3,7, 1,5,6, 1,6,2, 4,5,1, 4,1,0, 3,2,6, 3,6,7};
    ::bgfx::VertexLayout skyLayout;
    skyLayout.begin().add(::bgfx::Attrib::Position, 3, ::bgfx::AttribType::Float).end();
    skybox_vb_ = bgfx_->CreateVertexBuffer(bgfx_->Copy(kSkyVerts, sizeof(kSkyVerts)), skyLayout).idx;
    skybox_ib_ = bgfx_->CreateIndexBuffer(bgfx_->Copy(kSkyIdx, sizeof(kSkyIdx))).idx;

    // Uniforms
    sampler_uniform_       = bgfx_->CreateUniform("s_texColor",     ::bgfx::UniformType::Sampler).idx;
    env_map_uniform_       = bgfx_->CreateUniform("s_envMap",       ::bgfx::UniformType::Sampler).idx;
    color_uniform_         = bgfx_->CreateUniform("u_color",         ::bgfx::UniformType::Vec4).idx;
    light_dir_uniform_     = bgfx_->CreateUniform("u_lightDir",      ::bgfx::UniformType::Vec4).idx;
    light_color_uniform_   = bgfx_->CreateUniform("u_lightColor",    ::bgfx::UniformType::Vec4).idx;
    ambient_color_uniform_ = bgfx_->CreateUniform("u_ambientColor",  ::bgfx::UniformType::Vec4).idx;
    pbr_params_uniform_    = bgfx_->CreateUniform("u_pbrParams",     ::bgfx::UniformType::Vec4).idx;
    camera_pos_uniform_    = bgfx_->CreateUniform("u_cameraPos",     ::bgfx::UniformType::Vec4).idx;
    ibl_params_uniform_    = bgfx_->CreateUniform("u_iblParams",     ::bgfx::UniformType::Vec4).idx;
    normal_map_uniform_    = bgfx_->CreateUniform("s_normalMap",     ::bgfx::UniformType::Sampler).idx;
    normal_params_uniform_ = bgfx_->CreateUniform("u_normalParams",  ::bgfx::UniformType::Vec4).idx;
    skybox_sampler_uniform_ = bgfx_->CreateUniform("s_skybox",       ::bgfx::UniformType::Sampler).idx;
    skybox_tint_uniform_    = bgfx_->CreateUniform("u_skyboxTint",   ::bgfx::UniformType::Vec4).idx;
    shadow_map_uniform_     = bgfx_->CreateUniform("s_shadowMap",    ::bgfx::UniformType::Sampler).idx;
    light_vp_uniform_       = bgfx_->CreateUniform("u_lightVP",      ::bgfx::UniformType::Mat4).idx;
    shadow_params_uniform_  = bgfx_->CreateUniform("u_shadowParams", ::bgfx::UniformType::Vec4).idx;
    light_counts_uniform_   = bgfx_->CreateUniform("u_lightCounts",  ::bgfx::UniformType::Vec4).idx;
    point_lights_uniform_   = bgfx_->CreateUniform("u_pointLights",  ::bgfx::UniformType::Vec4, 128).idx;
    spot_lights_uniform_    = bgfx_->CreateUniform("u_spotLights",   ::bgfx::UniformType::Vec4, 192).idx;

    return KE_OK;
}

ke_render *BgfxRenderer::ToApi() { return &render_api_; }

void BgfxRenderer::set_bgfx(class BgfxBackend* bgfx)
{
    if (own_bgfx_ && bgfx_)
    {
        bgfx_->~BgfxBackend();
        allocator_->free(allocator_, bgfx_);
    }
    bgfx_ = bgfx;
    own_bgfx_ = false;
}

class BgfxBackend* BgfxRenderer::release_bgfx()
{
    class BgfxBackend* b = bgfx_;
    bgfx_ = nullptr;
    own_bgfx_ = false;
    return b;
}

} // namespace kernel_engine::render::bgfx

extern "C" {
    KE_RENDER_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_render **out_render) {
        if (!out_render || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;
        void *mem = params->allocator->alloc(params->allocator, sizeof(kernel_engine::render::bgfx::BgfxRenderer), alignof(kernel_engine::render::bgfx::BgfxRenderer));
        if (!mem) return KE_ERROR_OUT_OF_MEMORY;
        auto *renderer = new (mem) kernel_engine::render::bgfx::BgfxRenderer(params);
        *out_render = renderer->ToApi();
        return KE_OK;
    }
}
