#pragma once

#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/context/types.h>
#include <kernel_engine/core/engine/system.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_WINDOW_API
#ifdef _WIN32
#define KE_WINDOW_API __declspec(dllexport)
#else
#define KE_WINDOW_API __attribute__((visibility("default")))
#endif
#endif

    typedef struct ke_window_glfw_descriptor
    {
        struct ke_allocator *allocator;
        struct ke_logger *logger;
        struct ke_message_pipe *message_pipe;

        int width;
        int height;
        const char *title;
    } ke_window_glfw_descriptor;

    /**
     * @brief Creates the GLFW window system plugin.
     * @param desc The descriptor with necessary info (allocator is required).
     * @param out_system Pointer to receive the created system.
     * @return ke_result KE_OK on success, error code otherwise.
     */
    KE_WINDOW_API ke_result ke_window_glfw_create(const ke_window_glfw_descriptor *desc, ke_system **out_system);

#ifdef __cplusplus
}

namespace kernel_engine::domain::window
{
ke_result CreateGlfwWindowSystem(const ke_window_glfw_descriptor *desc, ke_system **out_system);
} // namespace kernel_engine::domain::window
#endif
