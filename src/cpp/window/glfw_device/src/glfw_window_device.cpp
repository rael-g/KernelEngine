#include "glfw_window_device.hpp"
#include <GLFW/glfw3.h>

#include <cstdint>

#if defined(_WIN32)
#  define GLFW_EXPOSE_NATIVE_WIN32
#  include <GLFW/glfw3native.h>
#elif defined(__linux__)
#  define GLFW_EXPOSE_NATIVE_X11
#  include <GLFW/glfw3native.h>
#endif

namespace kernel_engine::window
{

GlfwWindowDevice::~GlfwWindowDevice()
{
    Shutdown();
}

bool GlfwWindowDevice::Initialize(const WindowConfig& config)
{
    if (!glfwInit()) return false;

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API); // No GL context; the renderer owns the surface
    window_ = glfwCreateWindow(config.width, config.height, config.title, 
                                config.fullscreen ? glfwGetPrimaryMonitor() : nullptr, nullptr);
    
    if (!window_) return false;

    glfwSetWindowUserPointer(window_, this);

    // Register callbacks
    glfwSetKeyCallback(window_, KeyCallback);
    glfwSetCursorPosCallback(window_, CursorPosCallback);
    glfwSetMouseButtonCallback(window_, MouseButtonCallback);
    glfwSetScrollCallback(window_, ScrollCallback);
    glfwSetWindowSizeCallback(window_, WindowSizeCallback);
    glfwSetWindowCloseCallback(window_, WindowCloseCallback);

    return true;
}

void GlfwWindowDevice::Shutdown()
{
    if (window_) {
        glfwDestroyWindow(window_);
        window_ = nullptr;
    }
    glfwTerminate();
}

void GlfwWindowDevice::PollEvents(const std::function<void(const WindowEvent&)>& callback)
{
    event_callback_ = callback;
    glfwPollEvents();
}

bool GlfwWindowDevice::ShouldClose() const
{
    return window_ ? glfwWindowShouldClose(window_) : true;
}

void GlfwWindowDevice::SetTitle(const char* title)
{
    if (window_) glfwSetWindowTitle(window_, title);
}

void GlfwWindowDevice::GetSize(uint32_t* width, uint32_t* height) const
{
    if (window_) {
        int w, h;
        glfwGetWindowSize(window_, &w, &h);
        if (width) *width = (uint32_t)w;
        if (height) *height = (uint32_t)h;
    }
}

void* GlfwWindowDevice::GetNativeHandle() const
{
    if (!window_) return nullptr;
#if defined(_WIN32)
    return glfwGetWin32Window(window_);
#elif defined(__linux__)
    // An X11 window is an integer id rather than a pointer; it rides through
    // the void* slot as an integer-sized value and the consumer converts it
    // back. Returning the GLFWwindow* here would hand the surface layer a
    // pointer it would misread as a window id.
    return reinterpret_cast<void*>(static_cast<uintptr_t>(glfwGetX11Window(window_)));
#else
    return window_; // Placeholder for other platforms
#endif
}

// ── GLFW Callbacks ───────────────────────────────────────────────────────────

void GlfwWindowDevice::KeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    auto* self = static_cast<GlfwWindowDevice*>(glfwGetWindowUserPointer(window));
    if (!self->event_callback_) return;

    WindowEvent ev;
    ev.type = (action == GLFW_RELEASE) ? WindowEventType::KeyUp : WindowEventType::KeyDown;
    ev.data.key.key_code = (uint32_t)key;
    ev.data.key.alt   = (mods & GLFW_MOD_ALT) != 0;
    ev.data.key.ctrl  = (mods & GLFW_MOD_CONTROL) != 0;
    ev.data.key.shift = (mods & GLFW_MOD_SHIFT) != 0;
    self->event_callback_(ev);
}

void GlfwWindowDevice::CursorPosCallback(GLFWwindow* window, double xpos, double ypos)
{
    auto* self = static_cast<GlfwWindowDevice*>(glfwGetWindowUserPointer(window));
    if (!self->event_callback_) return;

    WindowEvent ev;
    ev.type = WindowEventType::MouseMove;
    ev.data.mouse_move.x = (float)xpos;
    ev.data.mouse_move.y = (float)ypos;
    self->event_callback_(ev);
}

void GlfwWindowDevice::MouseButtonCallback(GLFWwindow* window, int button, int action, int mods)
{
    auto* self = static_cast<GlfwWindowDevice*>(glfwGetWindowUserPointer(window));
    if (!self->event_callback_) return;

    WindowEvent ev;
    ev.type = (action == GLFW_RELEASE) ? WindowEventType::MouseButtonUp : WindowEventType::MouseButtonDown;
    ev.data.mouse_button.button = (uint8_t)button;
    self->event_callback_(ev);
}

void GlfwWindowDevice::ScrollCallback(GLFWwindow* window, double xoffset, double yoffset)
{
    auto* self = static_cast<GlfwWindowDevice*>(glfwGetWindowUserPointer(window));
    if (!self->event_callback_) return;

    WindowEvent ev;
    ev.type = WindowEventType::MouseScroll;
    ev.data.mouse_scroll.delta_x = (float)xoffset;
    ev.data.mouse_scroll.delta_y = (float)yoffset;
    self->event_callback_(ev);
}

void GlfwWindowDevice::WindowSizeCallback(GLFWwindow* window, int width, int height)
{
    auto* self = static_cast<GlfwWindowDevice*>(glfwGetWindowUserPointer(window));
    if (!self->event_callback_) return;

    WindowEvent ev;
    ev.type = WindowEventType::Resize;
    ev.data.resize.width = (uint32_t)width;
    ev.data.resize.height = (uint32_t)height;
    self->event_callback_(ev);
}

void GlfwWindowDevice::WindowCloseCallback(GLFWwindow* window)
{
    auto* self = static_cast<GlfwWindowDevice*>(glfwGetWindowUserPointer(window));
    if (!self->event_callback_) return;

    WindowEvent ev;
    ev.type = WindowEventType::Close;
    self->event_callback_(ev);
}

} // namespace kernel_engine::window
