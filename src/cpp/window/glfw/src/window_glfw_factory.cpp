#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/common/error.h>
#include <glfw_window_device.hpp>
#include <window_core.hpp>
#include <kernel_engine/allocator/allocator.h>
#include <new>

extern "C" {
    KE_WINDOW_API ke_window_handle ke_window_glfw_create(const ke_window_glfw_params* params, ke_error** out_error) {
        if (!params)
        {
            KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
            return {nullptr, nullptr};
        }

        // 1. Create the Hardware Implementation (Muscle)
        void* device_mem = ke_alloc(sizeof(kernel_engine::window::GlfwWindowDevice), alignof(kernel_engine::window::GlfwWindowDevice));
        if (!device_mem)
        {
            KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "device allocation failed");
            return {nullptr, nullptr};
        }
        auto* device = new (device_mem) kernel_engine::window::GlfwWindowDevice();

        // 2. Create the Agnostic Core (Brain)
        // Note: WindowCore handles its own deletion via api_struct_.destroy
        auto* core = new kernel_engine::window::WindowCore();

        // 3. Assemble: Inject Device and Input into Core
        core->SetDevice(device);
        core->SetInput(params->input);

        // 4. Initialize with params
        kernel_engine::window::WindowConfig config = {
            params->title,
            (uint32_t)params->width,
            (uint32_t)params->height,
            params->fullscreen != 0,
            true // Default VSync
        };

        if (!core->Initialize(config))
        {
            delete core;
            ke_free(device_mem);
            return {nullptr, nullptr};
        }

        // 5. Return the C-API interface
        return {core->ToApi(), &kernel_engine::window::WindowCore::DestroyApi};
    }
}
