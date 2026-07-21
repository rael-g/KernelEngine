#include <gtest/gtest.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/common/error.h>

// The window plugin's C ABI. Its internals — the backend-agnostic core and the
// GLFW device behind it — are covered by the plugin's own Zig tests, which can
// substitute a fake device for that seam. C++ no longer has a handle on it now
// that the implementation is Zig, so the mock-based core tests moved there.

TEST(WindowFactoryTest, Create_NullParams_ReturnsNullHandle) {
    ASSERT_EQ(ke_window_glfw_create(nullptr, nullptr).ref, nullptr);
}

TEST(WindowFactoryTest, Create_NullParams_ReportsInvalidArgument) {
    ke_error *err = nullptr;
    ASSERT_EQ(ke_window_glfw_create(nullptr, &err).ref, nullptr);
    ASSERT_NE(err, nullptr);
    ASSERT_NE(err->type, nullptr);
    EXPECT_STREQ(err->type->name, KE_ERROR_INVALID_ARGUMENT.name);
}

TEST(WindowFactoryTest, Create_Success_YieldsAUsableWindow) {
    ke_window_glfw_params params = { nullptr, nullptr, "Test", 800, 600, false };
    ke_window_handle w = ke_window_glfw_create(&params, nullptr);
    // A headless environment legitimately fails to open a window; both outcomes
    // are valid, but a live handle must actually work.
    if (w.ref == nullptr) GTEST_SKIP() << "no display available";

    int32_t width = 0, height = 0;
    EXPECT_TRUE(w.ref->get_size(w.ref, &width, &height, nullptr));
    EXPECT_GT(width, 0);
    EXPECT_GT(height, 0);
    EXPECT_NE(w.ref->get_native_handle(w.ref), nullptr);
    EXPECT_TRUE(w.ref->poll_events(w.ref, nullptr));
    w.destroy(w.ref);
}

TEST(WindowFactoryTest, Api_NullSelf_IsSafe) {
    ke_window_glfw_params params = { nullptr, nullptr, "Test", 320, 240, false };
    ke_window_handle w = ke_window_glfw_create(&params, nullptr);
    if (w.ref == nullptr) GTEST_SKIP() << "no display available";

    EXPECT_FALSE(w.ref->poll_events(nullptr, nullptr));
    EXPECT_TRUE(w.ref->should_close(nullptr));
    EXPECT_EQ(w.ref->get_native_handle(nullptr), nullptr);
    EXPECT_FALSE(w.ref->get_size(nullptr, nullptr, nullptr, nullptr));

    w.destroy(w.ref);
    w.destroy(nullptr); // destroying a null handle must not crash
}
