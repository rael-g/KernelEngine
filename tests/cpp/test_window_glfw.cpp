#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <GlfwWindow.hpp>
#include <GlfwInterface.hpp>
#include <memory>

using namespace kernel_engine::window::glfw;
using ::testing::Return;
using ::testing::_;
using ::testing::NiceMock;

// ── Professional Mocks ────────────────────────────────────────────────────

class MockGlfwBackend : public GlfwBackend {
public:
    MOCK_METHOD(int, Init, (), (override));
    MOCK_METHOD(void, Terminate, (), (override));
    MOCK_METHOD(void, WindowHint, (int, int), (override));
    MOCK_METHOD(GLFWwindow*, GlfwCreateWindow, (int, int, const char*, GLFWmonitor*, GLFWwindow*), (override));
    MOCK_METHOD(void, DestroyWindow, (GLFWwindow*), (override));
    MOCK_METHOD(void, SetWindowUserPointer, (GLFWwindow*, void*), (override));
    MOCK_METHOD(void*, GetWindowUserPointer, (GLFWwindow*), (override));
    MOCK_METHOD(GLFWkeyfun, SetKeyCallback, (GLFWwindow*, GLFWkeyfun), (override));
    MOCK_METHOD(void, PollEvents, (), (override));
    MOCK_METHOD(void, GetWindowSize, (GLFWwindow*, int*, int*), (override));
    MOCK_METHOD(int, WindowShouldClose, (GLFWwindow*), (override));
#ifdef _WIN32
    MOCK_METHOD(void*, GetWin32Window, (GLFWwindow*), (override));
#endif
};

// ── Test Suite ────────────────────────────────────────────────────────────

class GlfwWindowTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_window* window = nullptr;
    ke_logger* logger = nullptr;
    ke_message_pipe* pipe = nullptr;
    std::unique_ptr<NiceMock<MockGlfwBackend>> glfw_mock;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        
        logger = static_cast<ke_logger*>(calloc(1, sizeof(ke_logger)));
        logger->log = [](ke_logger*, const ke_log_event*) {};

        pipe = static_cast<ke_message_pipe*>(calloc(1, sizeof(ke_message_pipe)));
        pipe->broadcast = [](ke_message_pipe*, uint64_t, const void*, size_t) { return KE_OK; };

        ke_window_glfw_params params = { 
            alloc,
            logger,
            pipe,
            800,
            600,
            "Test"
        };
        ke_window_glfw_create(&params, &window);

        glfw_mock = std::make_unique<NiceMock<MockGlfwBackend>>();
        // Transfer ownership to test logic
        auto* impl = static_cast<GlfwWindow*>(window->handle);
        impl->set_glfw(glfw_mock.get());
    }

    void TearDown() override {
        if (window) {
            auto* impl = static_cast<GlfwWindow*>(window->handle);
            impl->set_glfw(nullptr); // Protect mock
            window->destroy(window);
        }
        if (pipe) free(pipe);
        if (logger) free(logger);
        if (alloc) alloc->destroy(alloc);
    }
};

// ── Creation Tests ────────────────────────────────────────────────────────

TEST(GlfwWindowInitTest, Create_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_window_glfw_create(nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST(GlfwWindowInitTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_window* w = nullptr;
    ASSERT_EQ(ke_window_glfw_create(nullptr, &w), KE_ERROR_INVALID_ARGUMENT);
}

TEST(GlfwWindowInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_window* w = nullptr;
    ke_window_glfw_params params = { nullptr, nullptr, nullptr, 800, 600, "Test" };
    ASSERT_EQ(ke_window_glfw_create(&params, &w), KE_ERROR_INVALID_ARGUMENT);
}

// ── Lifecycle Tests ───────────────────────────────────────────────────────

TEST_F(GlfwWindowTest, ToApi_ReturnsValidPointer) {
    ASSERT_NE(window, nullptr);
}

TEST_F(GlfwWindowTest, OnInitialize_Success) {
    ON_CALL(*glfw_mock, Init()).WillByDefault(Return(1));
    ON_CALL(*glfw_mock, GlfwCreateWindow(_, _, _, _, _)).WillByDefault(Return((GLFWwindow*)0x1234));
    
    ASSERT_EQ(window->on_initialize(window), KE_OK);
}

TEST_F(GlfwWindowTest, GetNativeHandle_BeforeInit_ReturnsNull) {
    ASSERT_EQ(window->get_native_handle(window), nullptr);
}

TEST_F(GlfwWindowTest, ShouldClose_BeforeInit_ReturnsTrue) {
    ASSERT_TRUE(window->should_close(window));
}

TEST_F(GlfwWindowTest, Lifecycle_FullRun) {
    ON_CALL(*glfw_mock, Init()).WillByDefault(Return(1));
    ON_CALL(*glfw_mock, GlfwCreateWindow(_, _, _, _, _)).WillByDefault(Return((GLFWwindow*)0x1234));
    ON_CALL(*glfw_mock, WindowShouldClose(_)).WillByDefault(Return(0));
    ON_CALL(*glfw_mock, GetWindowSize(_, _, _))
        .WillByDefault(::testing::Invoke([](GLFWwindow*, int* w, int* h) {
            if (w) *w = 800;
            if (h) *h = 600;
        }));
#ifdef _WIN32
    ON_CALL(*glfw_mock, GetWin32Window(_)).WillByDefault(Return((void*)0x5678));
#endif

    ASSERT_EQ(window->on_initialize(window), KE_OK);
    
#ifdef _WIN32
    ASSERT_NE(window->get_native_handle(window), nullptr);
#endif
    ASSERT_FALSE(window->should_close(window));
    
    int w, h;
    window->get_size(window, &w, &h);
    ASSERT_EQ(w, 800);
    ASSERT_EQ(h, 600);
    
    ASSERT_EQ(window->poll_events(window), KE_OK);
    ASSERT_EQ(window->on_shutdown(window), KE_OK);
}

TEST_F(GlfwWindowTest, OnShutdown_WithoutInit_DoesNotCrash) {
    ASSERT_EQ(window->on_shutdown(window), KE_OK);
}

// ── Destroy Tests ─────────────────────────────────────────────────────────

TEST_F(GlfwWindowTest, Destroy_Works) {
    window->destroy(window);
    window = nullptr;
    SUCCEED();
}

TEST_F(GlfwWindowTest, Destroy_NullSelf_DoesNotCrash) {
    auto destroy_fn = window->destroy;
    destroy_fn(nullptr);
    SUCCEED();
}
