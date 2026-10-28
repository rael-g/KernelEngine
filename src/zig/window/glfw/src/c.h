#ifndef KERNEL_ENGINE_WINDOW_GLFW_C_H_
#define KERNEL_ENGINE_WINDOW_GLFW_C_H_

#include <GLFW/glfw3.h>
#if defined(_WIN32)
#define GLFW_EXPOSE_NATIVE_WIN32 1
#elif defined(__linux__)
#define GLFW_EXPOSE_NATIVE_X11 1
#endif
#include <GLFW/glfw3native.h>

#endif
