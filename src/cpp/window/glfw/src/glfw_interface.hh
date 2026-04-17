#pragma once
#include <GLFW/glfw3.h>

namespace kernel_engine::window::glfw {

class GlfwBackend {
 public:
  virtual ~GlfwBackend() = default;

  virtual int Init() = 0;
  virtual void Terminate() = 0;
  virtual void WindowHint(int hint, int value) = 0;
  virtual GLFWwindow* GlfwCreateWindow(int width, int height, const char* title, GLFWmonitor* monitor, GLFWwindow* share) = 0;
  virtual void DestroyWindow(GLFWwindow* window) = 0;
  virtual void SetWindowUserPointer(GLFWwindow* window, void* pointer) = 0;
  virtual void* GetWindowUserPointer(GLFWwindow* window) = 0;
  virtual GLFWkeyfun SetKeyCallback(GLFWwindow* window, GLFWkeyfun callback) = 0;
  virtual void PollEvents() = 0;
  virtual void GetWindowSize(GLFWwindow* window, int* width, int* height) = 0;
  virtual int WindowShouldClose(GLFWwindow* window) = 0;
#ifdef _WIN32
  virtual void* GetWin32Window(GLFWwindow* window) = 0;
#endif
};

class RealGlfwBackend : public GlfwBackend {
 public:
  int Init() override { return glfwInit(); }
  void Terminate() override { glfwTerminate(); }
  void WindowHint(int hint, int value) override { glfwWindowHint(hint, value); }
  GLFWwindow* GlfwCreateWindow(int width, int height, const char* title, GLFWmonitor* monitor, GLFWwindow* share) override {
    return glfwCreateWindow(width, height, title, monitor, share);
  }
  void DestroyWindow(GLFWwindow* window) override { glfwDestroyWindow(window); }
  void SetWindowUserPointer(GLFWwindow* window, void* pointer) override { glfwSetWindowUserPointer(window, pointer); }
  void* GetWindowUserPointer(GLFWwindow* window) override { return glfwGetWindowUserPointer(window); }
  GLFWkeyfun SetKeyCallback(GLFWwindow* window, GLFWkeyfun callback) override { return glfwSetKeyCallback(window, callback); }
  void PollEvents() override { glfwPollEvents(); }
  void GetWindowSize(GLFWwindow* window, int* width, int* height) override { glfwGetWindowSize(window, width, height); }
  int WindowShouldClose(GLFWwindow* window) override { return glfwWindowShouldClose(window); }
#ifdef _WIN32
  void* GetWin32Window(GLFWwindow* window) override;
#endif
};

} // namespace kernel_engine::window::glfw
