#include <gtest/gtest.h>
#include <gmock/gmock.h>
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

TEST_F(GlfwWindowTest, FactoryAndToApi) {
    ASSERT_NE(window, nullptr);
    ASSERT_NE(window->handle, nullptr);
}

TEST_F(GlfwWindowTest, InitialState) {
    // Before OnInitialize, native handle is likely NULL
    ASSERT_EQ(window->get_native_handle(window), nullptr);
    ASSERT_TRUE(window->should_close(window));
}
