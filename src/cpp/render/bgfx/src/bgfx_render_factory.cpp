#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <core_renderer.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <new>

extern "C" {
    KE_RENDER_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_render **out_render) {
        if (!out_render || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;

        auto* alloc = params->allocator;

        // 1. Create the Hardware Implementation (Músculo)
        void* device_mem = alloc->alloc(alloc, sizeof(kernel_engine::render::bgfx::BgfxGpuDevice), alignof(kernel_engine::render::bgfx::BgfxGpuDevice));
        if (!device_mem) return KE_ERROR_OUT_OF_MEMORY;
        auto* device = new (device_mem) kernel_engine::render::bgfx::BgfxGpuDevice();

        // 2. Map C-API params to Agnostic HAL params
        kernel_engine::render::bgfx::GpuRendererParams core_params = {
            params->allocator,
            params->logger,
            params->shader_path,
            params->window,
            params->renderer_type
        };

        // 3. Create the Agnostic Core (Cérebro)
        void* renderer_mem = alloc->alloc(alloc, sizeof(kernel_engine::render::bgfx::CoreRenderer), alignof(kernel_engine::render::bgfx::CoreRenderer));
        if (!renderer_mem) {
            alloc->free(alloc, device_mem);
            return KE_ERROR_OUT_OF_MEMORY;
        }
        auto* renderer = new (renderer_mem) kernel_engine::render::bgfx::CoreRenderer(core_params);

        // 4. Assemble: Inject Device into Core
        renderer->SetGpuDevice(device);

        // 5. Return the C-API interface
        *out_render = renderer->ToApi();
        return KE_OK;
    }
}
