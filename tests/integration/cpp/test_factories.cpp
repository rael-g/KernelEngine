#include <gtest/gtest.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <kernel_engine/window/glfw/glfw_window.h>

TEST(FactoryIntegrationTest, RenderBgfx_Create_NullArgs_ReturnsInvalidArgument) {
    ke_render_handle r = ke_render_bgfx_create(nullptr, nullptr);
    ASSERT_EQ(r.ref, nullptr);

    ke_render_bgfx_params p{};
    ke_render_handle r2 = ke_render_bgfx_create(&p, nullptr);
    // p.window is null → expected to fail or succeed depending on implementation
    if (r2.ref) r2.destroy(r2.ref);
}

TEST(FactoryIntegrationTest, WindowGlfw_Create_NullArgs_ReturnsInvalidArgument) {
    ke_window_handle w = ke_window_glfw_create(nullptr, nullptr);
    ASSERT_EQ(w.ref, nullptr);
}
