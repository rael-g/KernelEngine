#include <gtest/gtest.h>
#include <GlfwWindow.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/kernel/input/input_messages.h>
#include <kernel_engine/kernel/logger/logger.h>
#include "GlfwInterface.hpp"
#include <vector>

using namespace kernel_engine::window::glfw;

// --- Pure Mock Message Pipe ---

struct MockPipeState {
    std::vector<std::pair<uint64_t, ke_msg_key_event>> messages;
};

static ke_result mock_pipe_broadcast(ke_message_pipe* self, uint64_t type, const void* data, size_t size) {
    if (type == KE_MSG_KEY_EVENT && size == sizeof(ke_msg_key_event)) {
        auto* state = static_cast<MockPipeState*>(self->handle);
        state->messages.push_back({type, *static_cast<const ke_msg_key_event*>(data)});
    }
    return KE_OK;
}

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
  void WindowHint(int hint, int value) override { (void)hint; (void)value; }
  GLFWwindow* GlfwCreateWindow(int width, int height, const char* title, GLFWmonitor* monitor, GLFWwindow* share) override { (void)width; (void)height; (void)title; (void)monitor; (void)share; return create_ret; }
  void DestroyWindow(GLFWwindow* window) override { (void)window; }
  void SetWindowUserPointer(GLFWwindow* window, void* pointer) override { (void)window; user_ptr = pointer; }
  void* GetWindowUserPointer(GLFWwindow* window) override { (void)window; return user_ptr; }
  GLFWkeyfun SetKeyCallback(GLFWwindow* window, GLFWkeyfun callback) override { (void)window; key_cb = callback; return nullptr; }
  void PollEvents() override { poll_count++; }
  void GetWindowSize(GLFWwindow* window, int* width, int* height) override { (void)window; *width = w; *height = h; }
  int WindowShouldClose(GLFWwindow* window) override { (void)window; return should_close; }
#ifdef _WIN32
  void* GetWin32Window(GLFWwindow* window) override { (void)window; return (void*)0x5678; }
#endif
};

class GlfwWindowMockTest : public ::testing::Test {
 protected:
  ke_allocator* alloc = nullptr;
  ke_message_pipe* pipe = nullptr;
  MockPipeState* pipe_state = nullptr;
  ke_logger* logger = nullptr;
  GlfwWindow* window_obj = nullptr;
  MockGlfwBackend* mock_glfw = nullptr;
  bool log_called = false;

  void SetUp() override {
    alloc = ke_allocator_malloc_create();
    
    // Create a pure mock pipe
    pipe = (ke_message_pipe*)calloc(1, sizeof(ke_message_pipe));
    pipe_state = new MockPipeState();
    pipe->handle = pipe_state;
    pipe->broadcast = mock_pipe_broadcast;
    pipe->destroy = [](ke_message_pipe* self) { (void)self; }; 

    logger = (ke_logger*)calloc(1, sizeof(ke_logger));
    logger->runtime_limit = KE_LOG_LEVEL_DEBUG;
    logger->log = [](ke_logger* self, const ke_log_event* ev) {
        (void)ev;
        if (!self->handle) return;
        auto* test = (GlfwWindowMockTest*)self->handle;
        test->log_called = true;
    };
    logger->handle = this;

    ke_window_glfw_params params = { alloc, logger, pipe, 800, 600, "Test" };
    window_obj = new GlfwWindow(&params);
    mock_glfw = new MockGlfwBackend();
    window_obj->set_glfw(mock_glfw);
  }

  void TearDown() override {
    if (window_obj) {
        window_obj->release_glfw();
        delete window_obj;
        window_obj = nullptr;
    }
    if (mock_glfw) {
        delete mock_glfw;
        mock_glfw = nullptr;
    }
    if (pipe) {
        free(pipe);
        pipe = nullptr;
    }
    if (pipe_state) {
        delete pipe_state;
        pipe_state = nullptr;
    }
    if (logger) {
        logger->handle = nullptr; // Neutralize callback
        free(logger);
        logger = nullptr;
    }
    if (alloc) {
        alloc->destroy(alloc);
        alloc = nullptr;
    }
  }
};

TEST_F(GlfwWindowMockTest, Initialize_Fail_LogsError) {
  mock_glfw->init_ret = 0;
  window_obj->OnInitialize();
  ASSERT_TRUE(log_called);
}

TEST_F(GlfwWindowMockTest, Initialize_Success_LogsInfo) {
  window_obj->OnInitialize();
  ASSERT_TRUE(log_called);
}

TEST_F(GlfwWindowMockTest, Shutdown_WithWindow_LogsInfo) {
  window_obj->OnInitialize();
  log_called = false;
  window_obj->OnShutdown();
  ASSERT_TRUE(log_called);
}

TEST_F(GlfwWindowMockTest, KeyCallback_BroadcastsMessage) {
  window_obj->OnInitialize();

  if (mock_glfw->key_cb) {
      mock_glfw->key_cb(mock_glfw->create_ret, 65, 0, 1, 0); // Key A, Press
  }

  ASSERT_FALSE(pipe_state->messages.empty());
  ASSERT_EQ(pipe_state->messages[0].first, KE_MSG_KEY_EVENT);
  ASSERT_EQ(pipe_state->messages[0].second.key, 65);
}

TEST_F(GlfwWindowMockTest, PollEvents_CallsBackend) {
  ke_window* api = window_obj->ToApi();
  api->poll_events(api);
  ASSERT_EQ(mock_glfw->poll_count, 1);
}

TEST_F(GlfwWindowMockTest, GetNativeHandle_NullWhenNoWindow) {
  ASSERT_EQ(window_obj->GetNativeHandle(), nullptr);
}

TEST_F(GlfwWindowMockTest, Destroy_ViaApi_Works) {
    ke_window_glfw_params p = { alloc, nullptr, nullptr, 800, 600, "API" };
    ke_window* win = nullptr;
    ke_window_glfw_create(&p, &win);
    
    win->destroy(win); 
    SUCCEED();
}
