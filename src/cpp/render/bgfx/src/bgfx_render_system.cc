#include <kernel_engine/render/bgfx/bgfx_render_system.hh>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/window/window.h>
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
    render_api_.clear_color = [](ke_render *self, float r, float g, float b, float a) {
        return static_cast<BgfxRenderSystem *>(self->handle)->ClearColor(r, g, b, a);
    };
    render_api_.submit = [](ke_render *self, const ke_mat4 *transform) {
        return static_cast<BgfxRenderSystem *>(self->handle)->Submit(transform);
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

ke_result BgfxRenderSystem::Submit(const ke_mat4 *transform) {
    if (!transform) return KE_ERROR_INVALID_ARGUMENT;
    ::bgfx::setTransform(transform->m);
    // Note: In a real engine, we'd set vertex buffers, shaders, etc. here.
    // For this example, we just touch the transform to verify the data flow.
    ::bgfx::submit(0, ::bgfx::ProgramHandle{program_});
    return KE_OK;
}

} // namespace kernel_engine::render::bgfx

extern "C" {
    ke_result ke_render_bgfx_create(const ke_render_bgfx_descriptor *desc, ke_render **out_render) {
        if (!out_render || !desc || !desc->allocator) return KE_ERROR_INVALID_ARGUMENT;
        void *mem = desc->allocator->alloc(desc->allocator, sizeof(kernel_engine::render::bgfx::BgfxRenderSystem), 0);
        auto *sys = new (mem) kernel_engine::render::bgfx::BgfxRenderSystem(desc);
        *out_render = sys->ToApi();
        return KE_OK;
    }
}
