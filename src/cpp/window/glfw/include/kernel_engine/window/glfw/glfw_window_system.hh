#pragma once

#include <kernel_engine/kernel/common/descriptor.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/kernel/window/window.h>
#include <kernel_engine/window/glfw/window_plugin.hh>
#include <string>

struct GLFWwindow;

namespace kernel_engine::window::glfw
{

class GlfwWindowSystem
{
  public:
    explicit GlfwWindowSystem(const ke_window_glfw_descriptor *desc);
    ~GlfwWindowSystem();

    ke_result OnInitialize();
    ke_result OnShutdown();

    [[nodiscard]] bool ShouldClose() const;
    ke_result GetSize(int *width, int *height) const;
    [[nodiscard]] void *GetNativeHandle() const;

    ke_window *ToApi();

    [[nodiscard]] ke_message_pipe *GetPipe() const
    {
        return pipe_api_;
    }

  private:
    int width_, height_;
    std::string title_;
    GLFWwindow *window_ = nullptr;

    ke_window window_api_{};

    ke_allocator *allocator_ = nullptr;
    ke_message_pipe *pipe_api_ = nullptr;
    ke_logger *logger_ = nullptr;
};
} // namespace kernel_engine::window::glfw
