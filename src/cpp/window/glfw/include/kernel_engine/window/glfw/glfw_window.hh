#pragma once

#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/window/window.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_WINDOW_API
    #ifdef KE_WINDOW_STATIC
        #define KE_WINDOW_API
    #else
        #ifdef KE_WINDOW_EXPORT
            #define KE_WINDOW_API KE_HELPER_EXPORT
        #else
            #define KE_WINDOW_API KE_HELPER_IMPORT
        #endif
    #endif
#endif

/// @brief Parameters for GLFW window creation.
typedef struct ke_window_glfw_params {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_message_pipe* message_pipe;
    int width;
    int height;
    const char* title;
} ke_window_glfw_params;

/**
 * @brief Creates the GLFW window system implementation.
 */
KE_WINDOW_API ke_result ke_window_glfw_create(const ke_window_glfw_params* params, ke_window** out_window);

#ifdef __cplusplus
}
#endif
