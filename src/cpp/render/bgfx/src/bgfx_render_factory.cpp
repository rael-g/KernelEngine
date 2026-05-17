#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <kernel_engine/kernel/render/render.h>
#include <core_renderer.hpp>
#include <bgfx_gpu_device.hpp>
#include <render_logging.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <bgfx/bgfx.h>
#include <new>

extern "C" {
    KE_RENDER_BGFX_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_render **out_render) {
        if (!out_render || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;

        auto* alloc = params->allocator;

        void* device_mem = alloc->alloc(alloc, sizeof(kernel_engine::render::bgfx::BgfxGpuDevice), alignof(kernel_engine::render::bgfx::BgfxGpuDevice));
        if (!device_mem) return KE_RENDER_LOG_ERR(params->logger, KE_ERROR_OUT_OF_MEMORY, "ke_render_bgfx_create", "Failed to allocate BgfxGpuDevice");
        auto* device = new (device_mem) kernel_engine::render::bgfx::BgfxGpuDevice();

        // renderer_type == 0 means "use engine default" → Vulkan
        uint32_t renderer_type = params->renderer_type == 0
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
            return KE_RENDER_LOG_ERR(params->logger, KE_ERROR_OUT_OF_MEMORY, "ke_render_bgfx_create", "Failed to allocate CoreRenderer");
        }
        auto* renderer = new (renderer_mem) kernel_engine::render::core::CoreRenderer(core_params);
        renderer->SetGpuDevice(device);

        *out_render = renderer->ToApi();
        return KE_OK;
    }
}
