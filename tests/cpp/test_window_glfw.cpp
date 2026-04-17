#include <gtest/gtest.h>
#include <kernel_engine/window/glfw/glfw_window.hh>
#include <kernel_engine/kernel/context/allocator.h>

class GlfwWindowTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_window* window = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ke_window_glfw_params params = { 
            .allocator = alloc,
            .width = 800,
            .height = 600,
            .title = "Test"
        };
        ke_window_glfw_create(&params, &window);
    }

    void TearDown() override {
        if (window) window->destroy(window);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Creation Tests ---

TEST(GlfwWindowInitTest, Create_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_window_glfw_create(nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST(GlfwWindowInitTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_window* w = nullptr;
    ASSERT_EQ(ke_window_glfw_create(nullptr, &w), KE_ERROR_INVALID_ARGUMENT);
}

TEST(GlfwWindowInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_window* w = nullptr;
    ke_window_glfw_params params = { .allocator = nullptr };
    ASSERT_EQ(ke_window_glfw_create(&params, &w), KE_ERROR_INVALID_ARGUMENT);
}

// --- Lifecycle Tests ---

TEST_F(GlfwWindowTest, ToApi_ReturnsValidPointer) {
    ASSERT_NE(window, nullptr);
}

TEST_F(GlfwWindowTest, OnInitialize_Success) {
    ASSERT_EQ(window->on_initialize(window), KE_OK);
}

TEST_F(GlfwWindowTest, GetNativeHandle_BeforeInit_ReturnsNull) {
    ASSERT_EQ(window->get_native_handle(window), nullptr);
}

TEST_F(GlfwWindowTest, ShouldClose_BeforeInit_ReturnsTrue) {
    ASSERT_TRUE(window->should_close(window));
}

TEST_F(GlfwWindowTest, Lifecycle_FullRun) {
    ASSERT_EQ(window->on_initialize(window), KE_OK);
    
    ASSERT_NE(window->get_native_handle(window), nullptr);
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

// --- Destroy Tests ---

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
