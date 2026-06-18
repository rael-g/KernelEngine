#pragma once

#include <kernel_engine/common/export.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/contract/window_export.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_window_glfw_params {
    struct ke_logger*     logger;
    struct ke_input*      input;
    const char*           title;
    int32_t               width;
    int32_t               height;
    bool               fullscreen;
} ke_window_glfw_params;

/**
 * @brief Creates a new window implementation using GLFW3.
 */
KE_WINDOW_API ke_result ke_window_glfw_create(const ke_window_glfw_params* params, ke_window_handle* out_window, ke_error** out_error);

#ifdef __cplusplus
}
#endif
