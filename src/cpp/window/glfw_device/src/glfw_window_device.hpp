#pragma once

#include <window_device.hpp>

// Forward declaration to avoid exposing GLFW in this header
struct GLFWwindow;

namespace kernel_engine::window
{

/**
 * @brief Implementation of WindowDeviceInterface using GLFW.
 * This is the ONLY place that should eventually know about GLFW3.
 */
class GlfwWindowDevice : public WindowDeviceInterface
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

private:
    GLFWwindow* window_ = nullptr;
    std::function<void(const WindowEvent&)> event_callback_;

    // Static callbacks for GLFW
    static void KeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods);
    static void CursorPosCallback(GLFWwindow* window, double xpos, double ypos);
    static void MouseButtonCallback(GLFWwindow* window, int button, int action, int mods);
    static void ScrollCallback(GLFWwindow* window, double xoffset, double yoffset);
    static void WindowSizeCallback(GLFWwindow* window, int width, int height);
    static void WindowCloseCallback(GLFWwindow* window);
};

} // namespace kernel_engine::window
