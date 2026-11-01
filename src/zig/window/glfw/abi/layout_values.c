#include <stddef.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/window/glfw/window_glfw_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_window_glfw_config),
    offsetof(ke_window_glfw_config, title),
    offsetof(ke_window_glfw_config, width),
    offsetof(ke_window_glfw_config, height),
    offsetof(ke_window_glfw_config, fullscreen),
    0,
};
