#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <kernel_engine/render/render.h>
#include <kernel_engine/common/error.h>
#include <core_renderer.hpp>
#include <bgfx_gpu_device.hpp>
#include <render_logging.hpp>
#include <kernel_engine/allocator/allocator.h>
#include <bgfx/bgfx.h>
#include <new>

extern "C" {
    KE_RENDER_BGFX_API ke_render_handle ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_error **out_error) {
        if (!params)
        {
            KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
            return {nullptr, nullptr};
        }

        void* device_mem = ke_alloc(sizeof(kernel_engine::render::bgfx::BgfxGpuDevice), alignof(kernel_engine::render::bgfx::BgfxGpuDevice));
        if (!device_mem)
        {
            KE_RENDER_LOG_ERR(params->logger, false, "ke_render_bgfx_create", "Failed to allocate BgfxGpuDevice");
            return {nullptr, nullptr};
        }
        auto* device = new (device_mem) kernel_engine::render::bgfx::BgfxGpuDevice();

        // renderer_type == UINT32_MAX means "auto-pick" (default -> Vulkan). Real bgfx values
        // start at 0 (RendererType::Noop), so UINT32_MAX is a sentinel that can never collide
        // with a legitimate user choice — including Noop, which is a valid headless backend.
        uint32_t renderer_type = params->renderer_type == UINT32_MAX
            ? (uint32_t)::bgfx::RendererType::Vulkan
            : params->renderer_type;

        kernel_engine::render::GpuRendererParams core_params = {
            params->logger,
            params->shader_path,
            params->window,
            renderer_type,
            params->vsync != 0
        };

        void* renderer_mem = ke_alloc(sizeof(kernel_engine::render::core::CoreRenderer), alignof(kernel_engine::render::core::CoreRenderer));
        if (!renderer_mem)
        {
            ke_free(device_mem);
            KE_RENDER_LOG_ERR(params->logger, false, "ke_render_bgfx_create", "Failed to allocate CoreRenderer");
            return {nullptr, nullptr};
        }
        auto* renderer = new (renderer_mem) kernel_engine::render::core::CoreRenderer(core_params);
        renderer->SetGpuDevice(device);

        return {renderer->ToApi(), &kernel_engine::render::core::CoreRenderer::DestroyApi};
    }
}
