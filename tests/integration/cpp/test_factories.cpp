#include <gtest/gtest.h>
#include <kernel_engine/window/glfw/glfw_window.h>

TEST(FactoryIntegrationTest, WindowGlfw_Create_NullArgs_ReturnsInvalidArgument) {
    ke_window_handle w = ke_window_glfw_create(nullptr, nullptr);
    ASSERT_EQ(w.ref, nullptr);
}
