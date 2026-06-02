#pragma once

#include <window_device.hpp>

// Forward declaration to avoid exposing GLFW in this header
struct GLFWwindow;

namespace kernel_engine::window
{

/**
 * @brief Implementation of WindowDevice using GLFW.
 * This is the ONLY place that should eventually know about GLFW3.
 */
class GlfwWindowDevice : public WindowDevice
{
public:
    GlfwWindowDevice() = default;
    virtual ~GlfwWindowDevice() override;

    bool Initialize(const WindowConfig& config) override;
    void Shutdown() override;
    void PollEvents(const std::function<void(const WindowEvent&)>& callback) override;
    bool ShouldClose() const override;

    void SetTitle(const char* title) override;
    void GetSize(uint32_t* width, uint32_t* height) const override;
    void* GetNativeHandle() const override;

    // GLFW-typed accessor for code that needs to drive the GLFW C API directly
    // (e.g. registering extra callbacks from a GLFW-specific input plugin, or
    // simulating events in unit tests). Distinct from GetNativeHandle() —
    // that returns the OS-native handle (Win32 HWND), which the renderer uses.
    GLFWwindow* GetGlfwWindow() const { return window_; }

    // Static GLFW C callbacks. Public because they are forwarders: GLFW invokes
    // them with the raw event, they fetch the owning device via the window's
    // user pointer, translate to WindowEvent, and dispatch through
    // event_callback_. They do not touch private state directly, so exposing
    // them does not break encapsulation — and it lets tests drive the same
    // translation path without a live OS event.
    static void KeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods);
    static void CursorPosCallback(GLFWwindow* window, double xpos, double ypos);
    static void MouseButtonCallback(GLFWwindow* window, int button, int action, int mods);
    static void ScrollCallback(GLFWwindow* window, double xoffset, double yoffset);
    static void WindowSizeCallback(GLFWwindow* window, int width, int height);
    static void WindowCloseCallback(GLFWwindow* window);

private:
    GLFWwindow* window_ = nullptr;
    std::function<void(const WindowEvent&)> event_callback_;
};

} // namespace kernel_engine::window
