#pragma once

#include <kernel_engine/core/engine/system.h>
#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/context/types.h>

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

/// @brief Configuration for the GLFW window system.
typedef struct ke_window_glfw_descriptor {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_message_pipe* message_pipe;
    int width;
    int height;
    const char* title;
} ke_window_glfw_descriptor;

/**
 * @brief Creates the GLFW window system plugin.
 */
KE_WINDOW_API ke_result ke_window_glfw_create(const ke_window_glfw_descriptor* desc, ke_system** out_system);

#ifdef __cplusplus
}
#endif
