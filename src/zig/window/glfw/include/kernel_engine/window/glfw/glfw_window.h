// ke_window_glfw_create — factory for the GLFW-backed window (the only export
// this plugin has; everything else it offers is reached through the ke_window
// vtable the factory returns).

#pragma once

#include <kernel_engine/window/window.h>

#ifndef KE_WINDOW_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    if defined(KE_WINDOW_STATIC)
#      define KE_WINDOW_API
#    elif defined(KE_WINDOW_EXPORT)
#      define KE_WINDOW_API __declspec(dllexport)
#    else
#      define KE_WINDOW_API __declspec(dllimport)
#    endif
#  else
#    define KE_WINDOW_API __attribute__((visibility("default")))
#  endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_window_glfw_params {
    struct ke_logger *logger;
    struct ke_input  *input;
    const char       *title;
    int32_t           width;
    int32_t           height;
    bool              fullscreen;
} ke_window_glfw_params;

/// Creates a GLFW-backed window. Returns a handle whose `ref` is NULL on failure.
KE_WINDOW_API ke_window_handle ke_window_glfw_create(const ke_window_glfw_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif
