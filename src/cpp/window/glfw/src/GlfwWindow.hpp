#pragma once

#include <kernel_engine/kernel/window/window.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <string>

struct GLFWwindow;

namespace kernel_engine::window::glfw
{

class KE_WINDOW_API GlfwWindow
{
public:
    explicit GlfwWindow(const ke_window_glfw_params *params);
    ~GlfwWindow();

    ke_result OnInitialize();
    ke_result OnShutdown();

    [[nodiscard]] ke_bool ShouldClose() const;
    void *GetNativeHandle() const;
    ke_result GetSize(int32_t *w, int32_t *h) const;

    ke_window *ToApi();
    ke_message_pipe *GetPipe() const { return pipe_api_; }

    // Test support
    void set_glfw(class GlfwBackend* glfw);
    class GlfwBackend* release_glfw();

private:
    ke_window window_api_{};
    GLFWwindow *window_ = nullptr;
    int32_t width_, height_;
    std::string title_;
    ke_allocator *allocator_;
    ke_message_pipe *pipe_api_;
    struct ke_logger *logger_;
    class GlfwBackend* glfw_ = nullptr;
    bool own_glfw_ = true;
};

} // namespace kernel_engine::window::glfw
