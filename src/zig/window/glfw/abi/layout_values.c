#include <stddef.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/window/glfw/window_glfw_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_window_glfw_params),
    offsetof(ke_window_glfw_params, input),
    offsetof(ke_window_glfw_params, title),
    offsetof(ke_window_glfw_params, width),
    offsetof(ke_window_glfw_params, height),
    offsetof(ke_window_glfw_params, fullscreen),
    0,
};
