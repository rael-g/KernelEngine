#include <kernel_engine/render/bgfx/bgfx_render_system.hh>
#include <kernel_engine/core/common/hash.h>
#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/window/window.h>
#include <new>
#include <bgfx/bgfx.h>
#include <bgfx/platform.h>
#include <fstream>
#include <string>

namespace kernel_engine::render::bgfx
{

BgfxRenderSystem::BgfxRenderSystem(const ke_render_bgfx_descriptor *desc)
    : allocator_(desc->allocator), logger_(desc->logger), window_(desc->window),
      shader_path_((desc->shader_path != nullptr) ? desc->shader_path : "")
{
    render_api_.handle = this;
    render_api_.clear_color = [](ke_render *self, float r, float g, float b, float a) {
        return static_cast<BgfxRenderSystem *>(self->handle)->ClearColor(r, g, b, a);
    };

    engine_api_.handle = &render_api_; // Correct: Point to C struct
    engine_api_.numeric_id = ke_hash_string("ke_render_bgfx");
    engine_api_.on_initialize = [](ke_system *self) {
        auto* api = static_cast<ke_render*>(self->handle);
        return static_cast<BgfxRenderSystem *>(api->handle)->OnInitialize();
    };
    engine_api_.on_shutdown = [](ke_system *self) {
        auto* api = static_cast<ke_render*>(self->handle);
        return static_cast<BgfxRenderSystem *>(api->handle)->OnShutdown();
    };
    engine_api_.on_update = [](ke_system *self, const ke_frame *frame) {
        (void)frame;
        ::bgfx::touch(0);
        ::bgfx::frame();
        return KE_OK;
    };
    engine_api_.destroy = [](ke_system *self) {
        auto *api = static_cast<ke_render *>(self->handle);
        auto *sys = static_cast<BgfxRenderSystem *>(api->handle);
        auto *alloc = sys->allocator_;
        sys->~BgfxRenderSystem();
        alloc->free(alloc, sys);
    };
}

BgfxRenderSystem::~BgfxRenderSystem() {}
uint64_t BgfxRenderSystem::Id() const { return engine_api_.numeric_id; }
ke_system *BgfxRenderSystem::ToApi() { return &engine_api_; }

ke_result BgfxRenderSystem::OnInitialize()
{
    if (!window_) return KE_ERROR_NOT_INITIALIZED;
    void *nwh = window_->get_native_handle(window_);
    if (!nwh) return KE_ERROR_WINDOW;

    ::bgfx::Init init;
    init.type = ::bgfx::RendererType::Count;
    init.platformData.nwh = nwh;
    
    int w, h;
    window_->get_size(window_, &w, &h);
    init.resolution.width = (uint32_t)w;
    init.resolution.height = (uint32_t)h;
    init.resolution.reset = BGFX_RESET_VSYNC;

    if (!::bgfx::init(init)) return KE_ERROR_RENDER;

    ::bgfx::setViewClear(0, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 0x303030ff, 1.0f, 0);
    ::bgfx::setViewRect(0, 0, 0, (uint16_t)w, (uint16_t)h);

    return SetupShader();
}

ke_result BgfxRenderSystem::SetupShader() { return KE_OK; }

ke_result BgfxRenderSystem::OnShutdown() { ::bgfx::shutdown(); return KE_OK; }

ke_result BgfxRenderSystem::ClearColor(float r, float g, float b, float a) {
    uint32_t color = (uint32_t(r * 255.0F) << 24) | (uint32_t(g * 255.0F) << 16) |
                   (uint32_t(b * 255.0F) << 8) | (uint32_t(a * 255.0F));
    ::bgfx::setViewClear(0, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, color, 1.0f, 0);
    return KE_OK;
}

} // namespace kernel_engine::render::bgfx

extern "C" {
    ke_result ke_render_bgfx_create(const ke_render_bgfx_descriptor *desc, ke_system **out_system) {
        if (!out_system || !desc || !desc->allocator) return KE_ERROR_INVALID_ARGUMENT;
        void *mem = desc->allocator->alloc(desc->allocator, sizeof(kernel_engine::render::bgfx::BgfxRenderSystem), 0);
        auto *sys = new (mem) kernel_engine::render::bgfx::BgfxRenderSystem(desc);
        *out_system = sys->ToApi();
        return KE_OK;
    }
}
