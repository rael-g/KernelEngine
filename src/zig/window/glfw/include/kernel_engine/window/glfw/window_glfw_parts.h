#ifndef KERNEL_ENGINE_WINDOW_GLFW_WINDOW_GLFW_PARTS_H_
#define KERNEL_ENGINE_WINDOW_GLFW_WINDOW_GLFW_PARTS_H_

#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_window_glfw contains: `window_glfw`, providing ke_window, with the slot `input`, `input`
 * optional.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_WINDOW_API const ke_part *ke_window_glfw_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
