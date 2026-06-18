#include <gtest/gtest.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <kernel_engine/window/glfw/glfw_window.h>

TEST(FactoryIntegrationTest, RenderBgfx_Create_NullArgs_ReturnsInvalidArgument) {
    ke_render_handle r{};
    ASSERT_EQ(ke_render_bgfx_create(nullptr, &r, nullptr), KE_ERROR);

    ke_render_bgfx_params p{};
    ASSERT_EQ(ke_render_bgfx_create(&p, nullptr, nullptr), KE_ERROR);
}

TEST(FactoryIntegrationTest, WindowGlfw_Create_NullArgs_ReturnsInvalidArgument) {
    ke_window_handle w{};
    ASSERT_EQ(ke_window_glfw_create(nullptr, &w, nullptr), KE_ERROR);

    ke_window_glfw_params p{};
    ASSERT_EQ(ke_window_glfw_create(&p, nullptr, nullptr), KE_ERROR);
}
