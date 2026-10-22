
#ifndef KERNEL_ENGINE_WINDOW_GLFW_GLFW_WINDOW_H_
#define KERNEL_ENGINE_WINDOW_GLFW_GLFW_WINDOW_H_

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
    struct ke_input  *input;  /**< [borrowed,nullable] Optional input sink target. */
    const char       *title;  /**< [borrowed,utf8] Window title. */
    int32_t           width;
    int32_t           height;
    bool              fullscreen;
} ke_window_glfw_params;

/**
 * Creates a window and starts it.
 * @param params [borrowed] The title, size, fullscreen flag and optional input sink.
 * @param out_window [out] Receives the window; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for null @p params or @p out_window;
 *         KE_RESULT_OUT_OF_MEMORY; KE_RESULT_GENERAL when the OS refuses the window.
 */
KE_WINDOW_API ke_result ke_window_glfw_create(const ke_window_glfw_params *params, ke_window_handle *out_window);

#ifdef __cplusplus
}
#endif

#endif
