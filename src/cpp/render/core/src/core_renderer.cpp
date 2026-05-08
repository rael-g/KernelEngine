#include <core_renderer.hpp>
#include <render_logging.hpp>
#include <geometry_manager.hpp>
#include <texture_manager.hpp>
#include <lighting_manager.hpp>
#include <shadow_pipeline.hpp>
#include <post_process_pipeline.hpp>
#include <clustered_forward.hpp>
#include <shader_provider.hpp>
#include <frame_submitter.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/window/window.h>
#include <new>
#include <cstring>
#include <fstream>
#include <cmath>
#include <stdarg.h>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

// ── CoreRenderer Implementation ───────────────────────────────────────────

CoreRenderer::CoreRenderer(const GpuRendererParams& params)
{
    window_       = params.window;
    shader_path_  = params.shader_path ? params.shader_path : "";
    renderer_type_ = params.renderer_type;
    vsync_        = params.vsync;

    std::memset(&ctx_, 0, sizeof(ctx_));
    std::memset(&render_api_, 0, sizeof(render_api_));
    
    ctx_.allocator = params.allocator;
    ctx_.logger    = params.logger;

    render_api_.handle = this;

    // Default shader provider (File system)
    if (ctx_.allocator) {
        void* provider_mem = ctx_.allocator->alloc(ctx_.allocator, sizeof(FileShaderProvider), alignof(FileShaderProvider));
        if (provider_mem) {
            ctx_.shader_provider = new (provider_mem) FileShaderProvider(shader_path_);
            own_shader_provider_ = true;
        }
    }
    
    // Wire up the C API dispatchers
    render_api_.on_initialize = [](ke_render *self) { 
        return (self && self->handle) ? static_cast<CoreRenderer *>(self->handle)->OnInitialize() : KE_ERROR_INVALID_ARGUMENT; 
    };
    render_api_.on_shutdown = [](ke_render *self) { 
        return (self && self->handle) ? static_cast<CoreRenderer *>(self->handle)->OnShutdown() : KE_ERROR_INVALID_ARGUMENT; 
    };
    render_api_.destroy = [](ke_render *self) {
        if (!self || !self->handle) return;
        auto *sys = static_cast<CoreRenderer *>(self->handle);
        auto *alloc = sys->ctx_.allocator;
        sys->~CoreRenderer();
        if (alloc) alloc->free(alloc, sys);
    };
    render_api_.frame = [](ke_render *self) { 
        return (self && self->handle) ? static_cast<CoreRenderer *>(self->handle)->Frame() : KE_ERROR_INVALID_ARGUMENT; 
    };
    render_api_.submit_packet = [](ke_render *self, const struct ke_frame_packet *packet) {
        return (self && self->handle) ? static_cast<CoreRenderer *>(self->handle)->SubmitPacket(packet) : KE_ERROR_INVALID_ARGUMENT;
    };
    render_api_.clear_color = [](ke_render *self, float r, float g, float b, float a) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->ClearColor(r, g, b, a);
    };
    render_api_.set_orthographic = [](ke_render *self, ke_bool enabled) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->SetOrthographic(enabled);
    };
    render_api_.set_view_transform = [](ke_render *self, const ke_mat4 *view, const ke_mat4 *proj) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->SetViewTransform(view, proj);
    };
    render_api_.create_texture_rgba = [](ke_render *self, uint32_t w, uint32_t h, const uint8_t *px, ke_texture_handle *out) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->textures_.CreateTextureRgba(renderer_impl->ctx_, w, h, px, out);
    };
    render_api_.destroy_texture = [](ke_render *self, ke_texture_handle handle) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->textures_.DestroyTexture(renderer_impl->ctx_, handle);
    };
    render_api_.create_mesh = [](ke_render *self, const ke_vertex *v, uint32_t vc, const uint16_t *i, uint32_t ic, ke_mesh_handle *out) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->geometry_.CreateMesh(renderer_impl->ctx_, v, vc, i, ic, out);
    };
    render_api_.destroy_mesh = [](ke_render *self, ke_mesh_handle h) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->geometry_.DestroyMesh(renderer_impl->ctx_, h);
    };
    render_api_.submit_mesh = [](ke_render *self, ke_mesh_handle m, ke_material_handle mat, const ke_mat4 *t) {
        return KE_OK; 
    };
    render_api_.create_cubemap_rgba = [](ke_render *self, uint32_t s, const uint8_t *d, ke_texture_handle *out) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->textures_.CreateCubemapRgba(renderer_impl->ctx_, s, d, out);
    };
    render_api_.submit_skybox = [](ke_render *self, ke_texture_handle h) {
        return KE_OK;
    };
    render_api_.set_tonemapping = [](ke_render *self, ke_bool e, float ex, float g) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->post_process_.SetTonemapping(renderer_impl->ctx_, e, ex, g);
    };
    render_api_.set_bloom = [](ke_render *self, ke_bool e, float t, float i) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->post_process_.SetBloom(renderer_impl->ctx_, e, t, i);
    };
    render_api_.create_shadow_map = [](ke_render *self, uint32_t w, uint32_t h, ke_shadow_map_handle *out) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->shadows_.CreateShadowMap(renderer_impl->ctx_, w, h, out);
    };
    render_api_.destroy_shadow_map = [](ke_render *self, ke_shadow_map_handle h) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->shadows_.DestroyShadowMap(renderer_impl->ctx_, h);
    };
    render_api_.begin_shadow_pass = [](ke_render *self, ke_shadow_map_handle h, const ke_mat4 *v, const ke_mat4 *p) {
        return KE_OK;
    };
    render_api_.submit_mesh_shadow = [](ke_render *self, ke_mesh_handle m, const ke_mat4 *t) {
        return KE_OK;
    };
    render_api_.end_shadow_pass = [](ke_render *self) {
        return KE_OK;
    };
    render_api_.set_shadow_map = [](ke_render *self, ke_shadow_map_handle h) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->shadows_.SetShadowMap(renderer_impl->ctx_, h);
    };
    render_api_.create_material = [](ke_render *self, const ke_material *m, ke_material_handle *out) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->lighting_.CreateMaterial(renderer_impl->ctx_, renderer_impl->textures_, m, out);
    };
    render_api_.destroy_material = [](ke_render *self, ke_material_handle h) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->lighting_.DestroyMaterial(renderer_impl->ctx_, h);
    };
    render_api_.set_directional_light = [](ke_render *self, const ke_directional_light *l) {
        return (self && self->handle) ? static_cast<CoreRenderer *>(self->handle)->lighting_.SetDirectionalLight(l) : KE_ERROR_INVALID_ARGUMENT; 
    };
    render_api_.set_ambient_light = [](ke_render *self, float r, float g, float b) {
        return (self && self->handle) ? static_cast<CoreRenderer *>(self->handle)->lighting_.SetAmbientLight(r, g, b) : KE_ERROR_INVALID_ARGUMENT; 
    };
    render_api_.set_point_lights = [](ke_render *self, const ke_point_light *ls, uint32_t c) {
        return KE_OK;
    };
    render_api_.set_spot_lights = [](ke_render *self, const ke_spot_light *ls, uint32_t c) {
        return KE_OK;
    };
    render_api_.set_camera_pos = [](ke_render *self, float x, float y, float z) {
        return (self && self->handle) ? static_cast<CoreRenderer *>(self->handle)->SetCameraPos(x, y, z) : KE_ERROR_INVALID_ARGUMENT; 
    };
    render_api_.set_ssao = [](ke_render *self, ke_bool e, float r, float b, float s) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->post_process_.SetSsao(renderer_impl->ctx_, e, r, b, s);
    };
    render_api_.set_cluster_config = [](ke_render *self, const ke_cluster_config *cfg) {
        if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
        auto* renderer_impl = static_cast<CoreRenderer *>(self->handle);
        return renderer_impl->clustered_.SetClusterConfig(renderer_impl->ctx_, cfg);
    };
}

CoreRenderer::~CoreRenderer()
{
    if (own_gpu_device_ && ctx_.gpu) {
        ctx_.gpu->~GpuDevice();
        if (ctx_.allocator) ctx_.allocator->free(ctx_.allocator, ctx_.gpu);
    }
    if (own_shader_provider_ && ctx_.shader_provider)
    {
        ctx_.shader_provider->~ShaderProviderInterface();
        if (ctx_.allocator) ctx_.allocator->free(ctx_.allocator, ctx_.shader_provider);
    }
}

void CoreRenderer::SetShaderProvider(ShaderProviderInterface* provider)
{
    if (own_shader_provider_ && ctx_.shader_provider)
    {
        ctx_.shader_provider->~ShaderProviderInterface();
        if (ctx_.allocator) ctx_.allocator->free(ctx_.allocator, ctx_.shader_provider);
    }
    ctx_.shader_provider = provider;
    own_shader_provider_ = false;
}

void CoreRenderer::SetGpuDevice(GpuDevice* gpu)
{
    if (own_gpu_device_ && ctx_.gpu) {
        ctx_.gpu->~GpuDevice();
        if (ctx_.allocator) ctx_.allocator->free(ctx_.allocator, ctx_.gpu);
    }
    ctx_.gpu = gpu;
    own_gpu_device_ = false;
    if (ctx_.gpu) ctx_.gpu->SetLogger(ctx_.logger);
}

ke_result CoreRenderer::OnInitialize()
{
    try {
        if (!ctx_.gpu) return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_RENDER, "OnInitialize", "GPU device not set");
        if (!window_) return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_NOT_INITIALIZED, "OnInitialize", "Window is null");
        void *nwh = window_->get_native_handle(window_);
        if (!nwh) return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_WINDOW, "OnInitialize", "Native window handle is null");

        int32_t w, h;
        window_->get_size(window_, &w, &h);

        GpuInitConfig config = {};
        config.native_window_handle = nwh;
        config.width = (uint32_t)w;
        config.height = (uint32_t)h;
        config.renderer_type = renderer_type_;
        config.vsync = vsync_;
#ifndef NDEBUG
        config.debug = true;
#endif

        if (!ctx_.gpu->Init(config))
            return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_RENDER, "OnInitialize", "gpu->Init failed");

        if (ctx_.logger) {
            ke_log_event ev = { KE_LOG_LEVEL_INFO, "core_render", "gpu->Init success" };
            ctx_.logger->log(ctx_.logger, &ev);
        }

        ctx_.view_w = w;
        ctx_.view_h = h;

        ctx_.gpu->SetViewClear(0, 0x0002 /*DEPTH*/, 0, 1.0f, 0);
        ctx_.gpu->SetViewRect(0, 0, 0, (uint16_t)w, (uint16_t)h);

        ctx_.gpu->SetViewClear(1 /*SCENE*/, 0x0001 | 0x0002, 0x303030ff, 1.0f, 0);
        ctx_.gpu->SetViewRect(1, 0, 0, (uint16_t)w, (uint16_t)h);
        ctx_.gpu->SetViewMode(1, GpuViewMode::Sequential);

        ke_result res = SetupShader();
        if (res != KE_OK) return res;

        if (ctx_.logger) {
            ke_log_event ev = { KE_LOG_LEVEL_INFO, "core_render", "SetupShader success" };
            ctx_.logger->log(ctx_.logger, &ev);
        }

        res = post_process_.SetupPostProcess(ctx_, geometry_, bright_pass_program_, blur_program_, tonemap_program_);
        if (res != KE_OK) return res;

        res = post_process_.SetupSsao(ctx_, prepass_program_, ssao_program_, ssao_blur_program_);
        if (res != KE_OK) return res;

        res = clustered_.SetupClustered(ctx_, depth_program_, cull_program_);
        if (res != KE_OK) return res;

        if (ctx_.logger) {
            ke_log_event ev = { KE_LOG_LEVEL_INFO, "core_render", "Pipelines setup success" };
            ctx_.logger->log(ctx_.logger, &ev);
        }

        initialized_ = true;
        return KE_OK;
    } catch (const BgfxFatalException& e) {
        return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_GPU_FATAL, "OnInitialize", e.what());
    }
}

ke_result CoreRenderer::OnShutdown()
{
    try {
        textures_.Shutdown();
        geometry_.Shutdown();
        lighting_.Shutdown();
        shadows_.Shutdown();
        post_process_.Shutdown();
        clustered_.Shutdown(ctx_);

        if (ctx_.gpu) {
            if (ssao_blur_program_ != kGpuInvalidHandle)   ctx_.gpu->DestroyProgram(ssao_blur_program_);
            if (ssao_program_ != kGpuInvalidHandle)        ctx_.gpu->DestroyProgram(ssao_program_);
            if (prepass_program_ != kGpuInvalidHandle)     ctx_.gpu->DestroyProgram(prepass_program_);
            if (tonemap_program_ != kGpuInvalidHandle)     ctx_.gpu->DestroyProgram(tonemap_program_);
            if (blur_program_ != kGpuInvalidHandle)        ctx_.gpu->DestroyProgram(blur_program_);
            if (bright_pass_program_ != kGpuInvalidHandle) ctx_.gpu->DestroyProgram(bright_pass_program_);
            if (depth_program_ != kGpuInvalidHandle)       ctx_.gpu->DestroyProgram(depth_program_);
            if (cull_program_ != kGpuInvalidHandle)        ctx_.gpu->DestroyProgram(cull_program_);
            if (shadow_program_ != kGpuInvalidHandle)      ctx_.gpu->DestroyProgram(shadow_program_);
            if (skybox_program_ != kGpuInvalidHandle)      ctx_.gpu->DestroyProgram(skybox_program_);
            if (program_ != kGpuInvalidHandle)              ctx_.gpu->DestroyProgram(program_);

            ctx_.gpu->Shutdown();
        }
        initialized_ = false;
        return KE_OK;
    } catch (const BgfxFatalException& e) {
        return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_GPU_FATAL, "OnShutdown", e.what());
    }
}

ke_result CoreRenderer::Frame()
{
    try {
        if (!initialized_ || !ctx_.gpu) return KE_ERROR_NOT_INITIALIZED;
        ctx_.gpu->Touch(1);
        ctx_.gpu->Frame();
        
        textures_.has_skybox       = false;
        textures_.active_env_tex   = kGpuInvalidHandle;
        shadows_.active_shadow_handle = KE_SHADOW_MAP_NONE;
        return KE_OK;
    } catch (const BgfxFatalException& e) {
        return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_GPU_FATAL, "Frame", e.what());
    }
}

ke_result CoreRenderer::SubmitPacket(const struct ke_frame_packet* packet)
{
    try {
        if (!initialized_ || !ctx_.gpu || !packet) return KE_ERROR_NOT_INITIALIZED;

        // Extract near/far from proj matrix so clustered has current values.
        const float* p = packet->camera.proj.m;
        if (std::abs(p[10] - p[11]) > 0.0001f) {
            ctx_.near_z = p[14] / (p[10] + 1.0f);
            ctx_.far_z  = p[14] / (p[10] - 1.0f);
        }
        // Store view for clustered bounds.
        std::memcpy(ctx_.last_view, packet->camera.view.m, sizeof(float) * 16);
        std::memcpy(ctx_.last_proj, packet->camera.proj.m, sizeof(float) * 16);

        ke_result res = FrameSubmitter::Submit(ctx_, *packet, geometry_, lighting_, textures_, shadows_,
                                            post_process_, program_, shadow_program_, skybox_program_, prepass_program_);
        if (res != KE_OK) return res;

        // Clustered light culling (must run after scene uniforms are set).
        clustered_.UpdateClusterBounds(ctx_);
        clustered_.DispatchLightCull(ctx_, lighting_, cull_program_);

        // SSAO pass.
        if (post_process_.IsSsaoEnabled() && post_process_.GetGbufFb() != kGpuInvalidHandle)
        {
            ctx_.gpu->SetViewFrameBuffer(2, post_process_.GetGbufFb());
            ctx_.gpu->SetViewClear(2, 0x0001 | 0x0002, 0x00000000, 1.0f, 0);
            ctx_.gpu->SetViewRect(2, 0, 0, (uint16_t)ctx_.view_w, (uint16_t)ctx_.view_h);
            post_process_.SubmitSsao(ctx_, geometry_, textures_, ssao_program_, ssao_blur_program_);
        }

        // Post-process / tonemap.
        if (post_process_.GetHdrFb() != kGpuInvalidHandle)
        {
            ctx_.gpu->SetViewFrameBuffer(1, post_process_.GetHdrFb());
            post_process_.SubmitPostProcess(ctx_, geometry_, textures_,
                                            bright_pass_program_, blur_program_, tonemap_program_);
        }
        else
        {
            ctx_.gpu->SetViewFrameBuffer(1, kGpuInvalidHandle);
        }

        return KE_OK;
    } catch (const BgfxFatalException& e) {
        return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_GPU_FATAL, "SubmitPacket", e.what());
    }
}

ke_result CoreRenderer::SetOrthographic(ke_bool enabled) {
    orthographic_ = (enabled != 0);
    return KE_OK;
}

ke_result CoreRenderer::ClearColor(float r, float g, float b, float a)
{
    if (!initialized_ || !ctx_.gpu) return KE_ERROR_NOT_INITIALIZED;
    uint32_t color = (uint32_t(r * 255.0F) << 24) | (uint32_t(g * 255.0F) << 16) |
                     (uint32_t(b * 255.0F) << 8)  | (uint32_t(a * 255.0F));
    ctx_.gpu->SetViewClear(1, 0x0001 | 0x0002, color, 1.0f, 0);
    return KE_OK;
}

ke_result CoreRenderer::SetViewTransform(const ke_mat4 *view, const ke_mat4 *proj)
{
    if (!view || !proj || !ctx_.gpu) 
        return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_INVALID_ARGUMENT, "SetViewTransform", "Invalid arguments or GPU not set");
    std::memcpy(ctx_.last_view, view->m, sizeof(float) * 16);
    std::memcpy(ctx_.last_proj, proj->m, sizeof(float) * 16);

    float n = 0.1f;
    float f = 1000.0f;
    if (std::abs(proj->m[10] - proj->m[11]) > 0.0001f) {
        n = proj->m[14] / (proj->m[10] + 1.0f);
        f = proj->m[14] / (proj->m[10] - 1.0f);
    }
    
    if (std::abs(n - ctx_.near_z) > 0.0001f || std::abs(f - ctx_.far_z) > 0.0001f) {
        ctx_.near_z = n;
        ctx_.far_z  = f;
    }

    ctx_.gpu->SetViewTransform(0, view->m, proj->m);
    ctx_.gpu->SetViewTransform(2, view->m, proj->m);
    ctx_.gpu->SetViewTransform(3, view->m, proj->m);
    ctx_.gpu->SetViewTransform(1, view->m, proj->m);
    return KE_OK;
}

ke_result CoreRenderer::SetCameraPos(float x, float y, float z)
{
    ctx_.camera_pos[0] = x; ctx_.camera_pos[1] = y; ctx_.camera_pos[2] = z; ctx_.camera_pos[3] = 0.f;
    return KE_OK;
}

ke_result CoreRenderer::SetDirectionalLight(const ke_directional_light *light) {
    ke_result res = lighting_.SetDirectionalLight(light);
    if (res != KE_OK) return KE_RENDER_LOG_ERR(ctx_.logger, res, "SetDirectionalLight", "Failed");
    return KE_OK;
}

ke_result CoreRenderer::SetAmbientLight(float r, float g, float b) {
    return lighting_.SetAmbientLight(r, g, b);
}

ke_result CoreRenderer::SetPointLights(const ke_point_light *lights, uint32_t count) {
    return KE_OK;
}

ke_result CoreRenderer::SetSpotLights(const ke_spot_light *lights, uint32_t count) {
    return KE_OK;
}

ke_result CoreRenderer::SetClusterConfig(const ke_cluster_config *config) {
    if (!initialized_) return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_NOT_INITIALIZED, "SetClusterConfig", "Not initialized");
    return clustered_.SetClusterConfig(ctx_, config);
}

ke_result CoreRenderer::SetSsao(ke_bool enabled, float radius, float bias, float strength) {
    return post_process_.SetSsao(ctx_, enabled, radius, bias, strength);
}

ke_result CoreRenderer::SetTonemapping(ke_bool enabled, float exposure, float gamma) {
    return post_process_.SetTonemapping(ctx_, enabled, exposure, gamma);
}

ke_result CoreRenderer::SetBloom(ke_bool enabled, float threshold, float intensity) {
    return post_process_.SetBloom(ctx_, enabled, threshold, intensity);
}

GpuShaderHandle CoreRenderer::LoadShader(const char *name)
{
    if (!ctx_.shader_provider || !ctx_.gpu) return kGpuInvalidHandle;
    const GpuMemoryBuffer* mem = ctx_.shader_provider->LoadShaderBinary(ctx_, name);
    if (!mem) {
        KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_IO, "LoadShader", name);
        return kGpuInvalidHandle;
    }
    return ctx_.gpu->CreateShader(mem);
}

ke_result CoreRenderer::SetupShader()
{
    if (!ctx_.gpu) return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_RENDER, "SetupShader", "GPU device not set");

    // Default quad mesh at handle 0
    {
        static const ke_vertex kQuadVerts[4] = {
            {-0.5f,-0.5f,0.f,  0.f,0.f,1.f,  0.f,0.f,  1.f,0.f,0.f,1.f},
            { 0.5f,-0.5f,0.f,  0.f,0.f,1.f,  1.f,0.f,  1.f,0.f,0.f,1.f},
            { 0.5f, 0.5f,0.f,  0.f,0.f,1.f,  1.f,1.f,  1.f,0.f,0.f,1.f},
            {-0.5f, 0.5f,0.f,  0.f,0.f,1.f,  0.f,1.f,  1.f,0.f,0.f,1.f},
        };
        static const uint16_t kQuadIdx[6] = {0,1,2, 0,2,3};
        ke_mesh_handle quad_handle;
        geometry_.CreateMesh(ctx_, kQuadVerts, 4, kQuadIdx, 6, &quad_handle);
    }

    GpuShaderHandle vs = LoadShader("vs_basic");
    GpuShaderHandle fs = LoadShader("fs_basic");
    if (vs == kGpuInvalidHandle || fs == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_RENDER, "SetupShader", "Failed to load basic shaders");
    
    GpuProgramHandle prog = ctx_.gpu->CreateProgram(vs, fs, true);
    if (prog == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_RENDER, "SetupShader", "Failed to create basic program");
    program_ = prog;

    uint32_t white = 0xffffffff;
    ke_texture_handle white_handle;
    if (textures_.CreateTextureRgba(ctx_, 1, 1, reinterpret_cast<const uint8_t *>(&white), &white_handle) != KE_OK)
        return KE_RENDER_LOG_ERR(ctx_.logger, KE_ERROR_RENDER, "SetupShader", "Failed to create white texture");
    textures_.default_2d_tex = textures_.GetTextureIdx(white_handle);

    // Default white material at handle 0
    {
        ke_material white_mat = {1.f, 1.f, 1.f, 1.f, white_handle, 0.f, 1.f, KE_TEXTURE_NONE};
        ke_material_handle mat_handle;
        lighting_.CreateMaterial(ctx_, textures_, &white_mat, &mat_handle);
    }
    
    {
        static const uint8_t kWhiteCube[24] = { // 6 faces × 1×1×RGBA8
            0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
            0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
        };
        const GpuMemoryBuffer *mem = ctx_.gpu->Copy(kWhiteCube, 24);
        GpuTextureHandle h = ctx_.gpu->CreateTextureCube(1, false, 1, kTexFmtRGBA8, 0, mem);
        textures_.default_cube_tex = h;
    }

    auto load_extra = [this](const char* vs_n, const char* fs_n, GpuProgramHandle& out_p) {
        auto v = LoadShader(vs_n);
        auto f = LoadShader(fs_n);
        if (v != kGpuInvalidHandle && f != kGpuInvalidHandle) {
            auto p = ctx_.gpu->CreateProgram(v, f, true);
            if (p != kGpuInvalidHandle) out_p = p;
        }
    };

    load_extra("vs_shadow", "fs_shadow", shadow_program_);
    load_extra("vs_skybox", "fs_skybox", skybox_program_);

    struct SkyVert { float x, y, z; };
    static const SkyVert kSkyVerts[8] = {{-1,-1,-1}, {1,-1,-1}, {1,1,-1}, {-1,1,-1}, {-1,-1,1}, {1,-1,1}, {1,1,1}, {-1,1,1}};
    static const uint16_t kSkyIdx[36] = {0,1,2, 0,2,3, 5,4,7, 5,7,6, 4,0,3, 4,3,7, 1,5,6, 1,6,2, 4,5,1, 4,1,0, 3,2,6, 3,6,7};
    
    geometry_.skybox_vb = ctx_.gpu->CreateVertexBuffer(ctx_.gpu->Copy(kSkyVerts, sizeof(kSkyVerts)), kVertexLayoutPositionOnly);
    geometry_.skybox_ib = ctx_.gpu->CreateIndexBuffer(ctx_.gpu->Copy(kSkyIdx, sizeof(kSkyIdx)));

    textures_.sampler_uniform        = ctx_.gpu->CreateUniform("s_texColor",     GpuUniformType::Sampler, 1);
    textures_.ssao_blurred_uniform   = ctx_.gpu->CreateUniform("s_ssaoBlurred",  GpuUniformType::Sampler, 1);
    lighting_.env_map_uniform        = ctx_.gpu->CreateUniform("s_envMap",       GpuUniformType::Sampler, 1);
    lighting_.color_uniform          = ctx_.gpu->CreateUniform("u_color",         GpuUniformType::Vec4, 1);
    lighting_.light_dir_uniform      = ctx_.gpu->CreateUniform("u_lightDir",      GpuUniformType::Vec4, 1);
    lighting_.light_color_uniform    = ctx_.gpu->CreateUniform("u_lightColor",    GpuUniformType::Vec4, 1);
    lighting_.ambient_color_uniform  = ctx_.gpu->CreateUniform("u_ambientColor",  GpuUniformType::Vec4, 1);
    lighting_.pbr_params_uniform     = ctx_.gpu->CreateUniform("u_pbrParams",     GpuUniformType::Vec4, 1);
    lighting_.camera_pos_uniform     = ctx_.gpu->CreateUniform("u_cameraPos",     GpuUniformType::Vec4, 1);
    lighting_.ibl_params_uniform     = ctx_.gpu->CreateUniform("u_iblParams",     GpuUniformType::Vec4, 1);
    lighting_.normal_map_uniform     = ctx_.gpu->CreateUniform("s_normalMap",     GpuUniformType::Sampler, 1);
    lighting_.normal_params_uniform  = ctx_.gpu->CreateUniform("u_normalParams",  GpuUniformType::Vec4, 1);
    textures_.skybox_sampler_uniform = ctx_.gpu->CreateUniform("s_skybox",       GpuUniformType::Sampler, 1);
    textures_.skybox_tint_uniform    = ctx_.gpu->CreateUniform("u_skyboxTint",   GpuUniformType::Vec4, 1);
    shadows_.shadow_map_uniform      = ctx_.gpu->CreateUniform("s_shadowMap",    GpuUniformType::Sampler, 1);
    shadows_.light_vp_uniform        = ctx_.gpu->CreateUniform("u_lightVP",      GpuUniformType::Mat4, 1);
    shadows_.shadow_params_uniform   = ctx_.gpu->CreateUniform("u_shadowParams", GpuUniformType::Vec4, 1);
    lighting_.light_counts_uniform   = ctx_.gpu->CreateUniform("u_lightCounts",  GpuUniformType::Vec4, 1);
    lighting_.point_lights_uniform   = ctx_.gpu->CreateUniform("u_pointLights",  GpuUniformType::Vec4, 128);
    lighting_.spot_lights_uniform    = ctx_.gpu->CreateUniform("u_spotLights",   GpuUniformType::Vec4, 192);

    return KE_OK;
}

ke_render *CoreRenderer::ToApi() { return &render_api_; }

} // namespace kernel_engine::render::bgfx
