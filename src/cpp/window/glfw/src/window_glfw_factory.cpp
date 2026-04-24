#include <kernel_engine/window/glfw/glfw_window.h>
#include <glfw_window_device.hpp>
#include <window_core.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <new>

extern "C" {
    KE_WINDOW_API ke_result ke_window_glfw_create(const ke_window_glfw_params* params, ke_window** out_window) {
        if (!out_window || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;

        auto* alloc = params->allocator;

        // 1. Create the Hardware Implementation (Muscle)
        void* device_mem = alloc->alloc(alloc, sizeof(kernel_engine::window::GlfwWindowDevice), alignof(kernel_engine::window::GlfwWindowDevice));
        if (!device_mem) return KE_ERROR_OUT_OF_MEMORY;
        auto* device = new (device_mem) kernel_engine::window::GlfwWindowDevice();

        // 2. Create the Agnostic Core (Brain)
        // Note: WindowCore handles its own deletion via api_struct_.destroy
        auto* core = new kernel_engine::window::WindowCore();

        // 3. Assemble: Inject Device into Core
        core->SetDevice(device);

        // 4. Initialize with params
        kernel_engine::window::WindowConfig config = {
            params->title,
            (uint32_t)params->width,
            (uint32_t)params->height,
            params->fullscreen != 0,
            true // Default VSync
        };

        ke_result res = core->Initialize(config);
        if (res != KE_OK) {
            delete core;
            alloc->free(alloc, device_mem);
            return res;
        }

        // 5. Return the C-API interface
        *out_window = core->ToApi();
        return KE_OK;
    }
}
