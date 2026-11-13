
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

struct ke_input;

/**
 * Creates a window and starts it.
 * @param input [borrowed,optional] Input sink target.
 * @param config [borrowed] The window's values; Required; every field is read as given.
 * @param out_window [out] Receives the window; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for null @p out_window;
 *         KE_RESULT_OUT_OF_MEMORY; KE_RESULT_GENERAL when the OS refuses the window.
 */
KE_WINDOW_API ke_result ke_window_glfw_create(struct ke_input *input, const ke_window_config *config, ke_window_handle *out_window);

#ifdef __cplusplus
}
#endif

#endif
