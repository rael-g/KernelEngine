#pragma once

#include <kernel_engine/common/export.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/window/window.h>

#ifdef __cplusplus
extern "C" {
#endif

    struct ke_input;

#ifndef KE_WINDOW_API
    #ifdef KE_WINDOW_STATIC
        #define KE_WINDOW_API
    #else
        #ifdef KE_WINDOW_EXPORT
            #define KE_WINDOW_API KE_EXPORT
        #else
            #define KE_WINDOW_API KE_IMPORT
        #endif
    #endif
#endif

/// @brief Parameters for GLFW window creation.
typedef struct ke_window_glfw_params {
    struct ke_logger*     logger;
    struct ke_input*      input;
    const char*           title;
    int32_t               width;
    int32_t               height;
    bool               fullscreen;
} ke_window_glfw_params;

/**
 * @brief Creates the GLFW window system implementation.
 * @return Handle whose @c ref is NULL on failure.
 */
KE_WINDOW_API ke_window_handle ke_window_glfw_create(const ke_window_glfw_params* params, ke_error** out_error);

#ifdef __cplusplus
}
#endif
