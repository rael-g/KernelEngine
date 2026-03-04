#pragma once

#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/engine/frame.h>
#include <kernel_engine/core/engine/system.h>
#include <kernel_engine/core/logger/logger.h>
#include <kernel_engine/core/messaging/message_pipe.h>
#include <kernel_engine/core/window/window.h>
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

    [[nodiscard]] uint64_t Id() const;

    ke_result OnInitialize();
    ke_result OnShutdown();
    static ke_result OnUpdate(const ke_frame &frame);

    [[nodiscard]] bool ShouldClose() const;
    static ke_result PollEvents();
    static ke_result SwapBuffers();
    ke_result GetSize(int *width, int *height) const;
    [[nodiscard]] int GetWidth() const;
    [[nodiscard]] int GetHeight() const;
    [[nodiscard]] void *GetNativeHandle() const;

    ke_system *ToApi();

    [[nodiscard]] ke_message_pipe *GetPipe() const
    {
        return pipe_api_;
    }

    [[nodiscard]] ke_window* GetWindowApi()
    {
        return &window_api_;
    }

  private:
    int width_, height_;
    std::string title_;
    GLFWwindow *window_ = nullptr;

    ke_system engine_api_{};
    ke_window window_api_{};

    ke_allocator *allocator_ = nullptr;
    ke_message_pipe *pipe_api_ = nullptr;
    ke_logger *logger_ = nullptr;
};
} // namespace kernel_engine::window::glfw
