#include "bgfx_render_system.hh"
#include <cstdio>
#include <kernel_engine/core/common/hash.h>
#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/window/window.h>
#include <new>

#include <bgfx/bgfx.h>
#include <bgfx/platform.h>
#include <fstream>
#include <iostream>
#include <string>

namespace kernel_engine::domain::render
{

BgfxRenderSystem::BgfxRenderSystem(const ke_render_bgfx_descriptor *desc)
    : allocator_(desc->allocator), logger_(desc->logger), window_(desc->window),
      shader_path_((desc->shader_path != nullptr) ? desc->shader_path : "")
{
    render_api_.handle = this;
    render_api_.destroy = [](ke_render *self) { (void)self; };
    render_api_.set_orthographic = [](ke_render *self, bool enabled) {
        return static_cast<BgfxRenderSystem *>(self->handle)->SetOrthographic(enabled);
    };
    render_api_.clear_color = [](ke_render *self, float r, float g, float b, float a) {
        return static_cast<BgfxRenderSystem *>(self->handle)->ClearColor(r, g, b, a);
    };
    render_api_.draw_node = [](ke_render * /*self*/, void *node) {
        return kernel_engine::domain::render::BgfxRenderSystem::DrawNode(node);
    };
    render_api_.set_node_shape = [](ke_render * /*self*/, void *node, int shape) {
        return kernel_engine::domain::render::BgfxRenderSystem::SetNodeShape(node, shape);
    };
    render_api_.set_node_color = [](ke_render * /*self*/, void *node, float r, float g, float b, float a) {
        return kernel_engine::domain::render::BgfxRenderSystem::SetNodeColor(node, r, g, b, a);
    };

    engine_api_.handle = this;
    engine_api_.numeric_id = ke_hash_string("ke_render_bgfx");
    engine_api_.destroy = [](ke_system *self) {
        auto *sys = static_cast<BgfxRenderSystem *>(self->handle);
        auto *alloc = sys->allocator_;
        if (alloc)
        {
            sys->~BgfxRenderSystem();
            alloc->free(alloc, sys);
        }
    };
    engine_api_.on_initialize = [](ke_system *self) {
        return static_cast<BgfxRenderSystem *>(self->handle)->OnInitialize();
    };
    engine_api_.on_shutdown = [](ke_system *self) {
        return static_cast<BgfxRenderSystem *>(self->handle)->OnShutdown();
    };
    engine_api_.on_update = [](ke_system * /*self*/, const ke_frame *frame) {
        if (frame)
        {
            return kernel_engine::domain::render::BgfxRenderSystem::OnUpdate(*frame);
        }
        ke_frame dummy = {0, 0.0, 0.0};
        return kernel_engine::domain::render::BgfxRenderSystem::OnUpdate(dummy);
    };
}

BgfxRenderSystem::~BgfxRenderSystem() = default;

uint64_t BgfxRenderSystem::Id() const
{
    return engine_api_.numeric_id;
}
ke_system *BgfxRenderSystem::ToApi()
{
    return &engine_api_;
}

ke_result BgfxRenderSystem::OnInitialize()
{
    if (window_ == nullptr)
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "render", "BgfxRenderSystem: Window dependency not provided.");
        }
        return KE_ERROR_NOT_INITIALIZED;
    }

    void *native_handle = window_->get_native_handle(window_);
    if (native_handle == nullptr)
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "render", "BgfxRenderSystem: Window native handle not found.");
        }
        return KE_ERROR_WINDOW;
    }

    bgfx::Init init;
    init.type = bgfx::RendererType::Count;
    init.vendorId = BGFX_PCI_ID_NONE;
    init.platformData.nwh = native_handle;

    int width = 0;
    int height = 0;
    window_->get_size(window_, &width, &height);
    init.resolution.width = static_cast<uint32_t>(width);
    init.resolution.height = static_cast<uint32_t>(height);
    init.resolution.reset = BGFX_RESET_VSYNC;

    if (!bgfx::init(init))
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "render", "Failed to initialize bgfx.");
        }
        return KE_ERROR_RENDER;
    }

    bgfx::setViewClear(0, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, clear_color_, 1.0F, 0);
    bgfx::setViewRect(0, 0, 0, static_cast<uint16_t>(width), static_cast<uint16_t>(height));

    if (logger_ != nullptr)
    {
        logger_->log(logger_, KE_LOG_LEVEL_INFO, "render", "bgfx initialized successfully.");
    }

    return SetupShader();
}

ke_result BgfxRenderSystem::SetupShader()
{
    bgfx::ShaderHandle const vsh = {static_cast<uint16_t>((uintptr_t)LoadShader("vs_basic"))};
    bgfx::ShaderHandle const fsh = {static_cast<uint16_t>((uintptr_t)LoadShader("fs_basic"))};

    if (!bgfx::isValid(vsh) || !bgfx::isValid(fsh))
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "render", "Failed to load basic shaders.");
        }
        return KE_ERROR_RENDER;
    }

    bgfx::ProgramHandle const prog = bgfx::createProgram(vsh, fsh, true);
    program_ = prog.idx;

    if (!bgfx::isValid(prog))
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "render", "Failed to create shader program.");
        }
        return KE_ERROR_RENDER;
    }

    return KE_OK;
}

void *BgfxRenderSystem::LoadShader(const char *name)
{
    std::string shaderPath = shader_path_;
    if (!shaderPath.empty() && shaderPath.back() != '/' && shaderPath.back() != '\\')
    {
        shaderPath += "/";
    }
    shaderPath += name;
    shaderPath += ".bin";

    std::ifstream file(shaderPath, std::ios::binary | std::ios::ate);
    if (!file.is_open())
    {
        if (logger_ != nullptr)
        {
            std::string const msg = "Failed to open shader file: " + shaderPath;
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "render", msg.c_str());
        }
        return (void *)(uintptr_t)BGFX_INVALID_HANDLE;
    }

    std::streamsize const size = file.tellg();
    file.seekg(0, std::ios::beg);

    const bgfx::Memory *mem = bgfx::alloc(static_cast<uint32_t>(size));
    if (file.read(reinterpret_cast<char *>(mem->data), size))
    {
        bgfx::ShaderHandle const handle = bgfx::createShader(mem);
        return (void *)static_cast<uintptr_t>(handle.idx);
    }

    return (void *)(uintptr_t)BGFX_INVALID_HANDLE;
}

ke_result BgfxRenderSystem::OnShutdown()
{
    bgfx::shutdown();
    if (logger_ != nullptr)
    {
        logger_->log(logger_, KE_LOG_LEVEL_DEBUG, "render", "bgfx shutdown.");
    }
    return KE_OK;
}

ke_result BgfxRenderSystem::OnUpdate(const ke_frame &frame)
{
    (void)frame;
    bgfx::touch(0);
    bgfx::frame();
    return KE_OK;
}

ke_result BgfxRenderSystem::SetOrthographic(bool enabled)
{
    orthographic_ = enabled;
    return KE_OK;
}

ke_result BgfxRenderSystem::ClearColor(float r, float g, float b, float a)
{
    clear_color_ = (static_cast<uint32_t>(r * 255.0F) << 24) | (static_cast<uint32_t>(g * 255.0F) << 16) |
                   (static_cast<uint32_t>(b * 255.0F) << 8) | (static_cast<uint32_t>(a * 255.0F));
    bgfx::setViewClear(0, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, clear_color_, 1.0F, 0);
    return KE_OK;
}

ke_result BgfxRenderSystem::DrawNode(void *node_handle)
{
    (void)node_handle;
    return KE_OK;
}
ke_result BgfxRenderSystem::SetNodeShape(void *node_handle, int shape)
{
    (void)node_handle;
    (void)shape;
    return KE_OK;
}
ke_result BgfxRenderSystem::SetNodeColor(void *node_handle, float r, float g, float b, float a)
{
    (void)node_handle;
    (void)r;
    (void)g;
    (void)b;
    (void)a;
    return KE_OK;
}

} // namespace kernel_engine::domain::render

extern "C"
{

    ke_result ke_render_bgfx_create(const ke_render_bgfx_descriptor *desc, ke_system **out_system)
    {
        if (out_system == nullptr)
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }
        *out_system = NULL;

        if ((desc == nullptr) || (desc->allocator == nullptr))
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }
        using namespace kernel_engine::domain::render;
        ke_allocator *alloc = desc->allocator;

        void *mem = alloc->alloc(alloc, sizeof(BgfxRenderSystem), 0);
        if (mem == nullptr)
        {
            return KE_ERROR_OUT_OF_MEMORY;
        }

        BgfxRenderSystem *sys = new (mem) BgfxRenderSystem(desc);
        *out_system = sys->ToApi();
        return KE_OK;
    }
}
