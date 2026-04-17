#include <gtest/gtest.h>
#include <kernel_engine/window/glfw/glfw_window_system.hh>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/kernel/input/input_messages.h>
#include <kernel_engine/kernel/logger/logger.h>
#include "glfw_interface.hh"

using namespace kernel_engine::window::glfw;

class MockGlfwBackend : public GlfwBackend {
 public:
  int init_ret = 1;
  GLFWwindow* create_ret = (GLFWwindow*)0x1234;
  void* user_ptr = nullptr;
  GLFWkeyfun key_cb = nullptr;
  int should_close = 0;
  int w = 800, h = 600;
  int poll_count = 0;
  int term_count = 0;

  int Init() override { return init_ret; }
  void Terminate() override { term_count++; }
  void WindowHint(int hint, int value) override {}
  GLFWwindow* GlfwCreateWindow(int width, int height, const char* title, GLFWmonitor* monitor, GLFWwindow* share) override { return create_ret; }
  void DestroyWindow(GLFWwindow* window) override {}
  void SetWindowUserPointer(GLFWwindow* window, void* pointer) override { user_ptr = pointer; }
  void* GetWindowUserPointer(GLFWwindow* window) override { return user_ptr; }
  GLFWkeyfun SetKeyCallback(GLFWwindow* window, GLFWkeyfun callback) override { key_cb = callback; return nullptr; }
  void PollEvents() override { poll_count++; }
  void GetWindowSize(GLFWwindow* window, int* width, int* height) override { *width = w; *height = h; }
  int WindowShouldClose(GLFWwindow* window) override { return should_close; }
#ifdef _WIN32
  void* GetWin32Window(GLFWwindow* window) override { return (void*)0x5678; }
#endif
};

class GlfwWindowMockTest : public ::testing::Test {
 protected:
  ke_allocator* alloc = nullptr;
  ke_message_pipe* pipe = nullptr;
  ke_logger* logger = nullptr;
  GlfwWindowSystem* system = nullptr;
  MockGlfwBackend* mock_glfw = nullptr;
  bool log_called = false;

  void SetUp() override {
    alloc = ke_allocator_malloc_create();
    ke_message_pipe_create(alloc, nullptr, &pipe);
    
    logger = (ke_logger*)calloc(1, sizeof(ke_logger));
    logger->runtime_limit = KE_LOG_LEVEL_DEBUG;
    logger->log = [](ke_logger* self, const ke_log_event* ev) {
        auto* test = (GlfwWindowMockTest*)self->handle;
        test->log_called = true;
    };
    logger->handle = this;

    ke_window_glfw_params params = { alloc, logger, pipe, 800, 600, "Test" };
    system = new GlfwWindowSystem(&params);
    mock_glfw = new MockGlfwBackend();
    system->set_glfw(mock_glfw);
  }

  void TearDown() override {
    if (system) delete system;
    if (mock_glfw) delete mock_glfw;
    if (pipe) pipe->destroy(pipe);
    if (logger) free(logger);
    if (alloc) alloc->destroy(alloc);
  }
};

TEST_F(GlfwWindowMockTest, Initialize_Fail_LogsError) {
  mock_glfw->init_ret = 0;
  system->OnInitialize();
  ASSERT_TRUE(log_called);
}

TEST_F(GlfwWindowMockTest, Initialize_Success_LogsInfo) {
  system->OnInitialize();
  ASSERT_TRUE(log_called);
}

TEST_F(GlfwWindowMockTest, Shutdown_WithWindow_LogsInfo) {
  system->OnInitialize();
  log_called = false;
  system->OnShutdown();
  ASSERT_TRUE(log_called);
}

TEST_F(GlfwWindowMockTest, KeyCallback_BroadcastsMessage) {
  ke_message_pipe* reader = nullptr;
  pipe->create_reader(pipe, &reader);

  system->OnInitialize();

  // Trigger the callback with the mock's window handle
  if (mock_glfw->key_cb) {
      mock_glfw->key_cb(mock_glfw->create_ret, 65, 0, 1, 0); // Key A, Press
  }

  ke_msg_key_event received_msg = {};
  bool received = reader->try_receive(reader, KE_MSG_KEY_EVENT, &received_msg, sizeof(received_msg));

  ASSERT_TRUE(received);
  ASSERT_EQ(received_msg.key, 65);
  
  reader->destroy(reader);
}

TEST_F(GlfwWindowMockTest, PollEvents_CallsBackend) {
  ke_window* api = system->ToApi();
  api->poll_events(api);
  ASSERT_EQ(mock_glfw->poll_count, 1);
}

TEST_F(GlfwWindowMockTest, GetNativeHandle_NullWhenNoWindow) {
  ASSERT_EQ(system->GetNativeHandle(), nullptr);
}

TEST_F(GlfwWindowMockTest, Destroy_ViaApi_Works) {
    ke_window* api = system->ToApi();
    // In our implementation, destroy calls delete sys and free mem.
    // Since we managed system with new standard, we need to be careful.
    // But ke_window_glfw_create uses allocator->alloc.
    
    ke_window_glfw_params p = { alloc, nullptr, nullptr, 800, 600, "API" };
    ke_window* win = nullptr;
    ke_window_glfw_create(&p, &win);
    
    win->destroy(win); // Should not crash
    SUCCEED();
}
