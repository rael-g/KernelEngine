#pragma once

#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/window/window.h>
#include <window_export.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_window_glfw_params {
    struct ke_allocator*  allocator;
    struct ke_logger*     logger;
    struct ke_message_pipe* message_pipe;
    const char*           title;
    int32_t               width;
    int32_t               height;
    ke_bool               fullscreen;
} ke_window_glfw_params;

/**
 * @brief Creates a new window implementation using GLFW3.
 */
KE_WINDOW_API ke_result ke_window_glfw_create(const ke_window_glfw_params* params, ke_window** out_window);

#ifdef __cplusplus
}
#endif
