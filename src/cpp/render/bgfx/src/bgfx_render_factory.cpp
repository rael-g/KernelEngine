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
    KE_RENDER_BGFX_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_render_handle *out_render, ke_error **out_error) {
        if (!out_render || !params || !params->allocator) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");

        auto* alloc = params->allocator;

        void* device_mem = alloc->alloc(alloc, sizeof(kernel_engine::render::bgfx::BgfxGpuDevice), alignof(kernel_engine::render::bgfx::BgfxGpuDevice));
        if (!device_mem) return KE_RENDER_LOG_ERR(params->logger, KE_ERROR, "ke_render_bgfx_create", "Failed to allocate BgfxGpuDevice");
        auto* device = new (device_mem) kernel_engine::render::bgfx::BgfxGpuDevice();

        // renderer_type == UINT32_MAX means "auto-pick" (default → Vulkan). Real bgfx values
        // start at 0 (RendererType::Noop), so UINT32_MAX is a sentinel that can never collide
        // with a legitimate user choice — including Noop, which is a valid headless backend.
        uint32_t renderer_type = params->renderer_type == UINT32_MAX
            ? (uint32_t)::bgfx::RendererType::Vulkan
            : params->renderer_type;

        kernel_engine::render::GpuRendererParams core_params = {
            params->allocator,
            params->logger,
            params->shader_path,
            params->window,
            renderer_type,
            params->vsync != 0
        };

        void* renderer_mem = alloc->alloc(alloc, sizeof(kernel_engine::render::core::CoreRenderer), alignof(kernel_engine::render::core::CoreRenderer));
        if (!renderer_mem) {
            alloc->free(alloc, device_mem);
            return KE_RENDER_LOG_ERR(params->logger, KE_ERROR, "ke_render_bgfx_create", "Failed to allocate CoreRenderer");
        }
        auto* renderer = new (renderer_mem) kernel_engine::render::core::CoreRenderer(core_params);
        renderer->SetGpuDevice(device);

        out_render->ref     = renderer->ToApi();
        out_render->destroy = &kernel_engine::render::core::CoreRenderer::DestroyApi;
        return KE_OK;
    }
}
