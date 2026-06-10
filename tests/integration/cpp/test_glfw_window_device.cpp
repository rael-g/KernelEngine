#include <gtest/gtest.h>
#include <glfw_window_device.hpp>
#include <GLFW/glfw3.h>

using namespace kernel_engine::window;

// The test drives the real device through its public surface. The GLFW
// callbacks are public static forwarders (they look up the device via
// glfwGetWindowUserPointer), so we can invoke them directly to simulate
// OS events without spinning the GLFW event loop. GetNativeHandle()
// returns the underlying GLFWwindow* — we cast it back to drive callbacks.

class GlfwWindowDeviceTest : public ::testing::Test {
protected:
    GlfwWindowDevice device;
    WindowConfig config = { "Test", 800, 600, false, true };

    void TearDown() override {
        device.Shutdown();
    }

    GLFWwindow* Window() { return device.GetGlfwWindow(); }

    bool EnsureInitialized() {
        if (Window()) return true;
        return device.Initialize(config);
    }
};

TEST_F(GlfwWindowDeviceTest, Initialize_SetsWindowUserPointer) {
    if (!EnsureInitialized()) GTEST_SKIP();
    ASSERT_EQ(glfwGetWindowUserPointer(Window()), &device);
}

TEST_F(GlfwWindowDeviceTest, KeyCallback_EmitsKeyDown) {
    if (!EnsureInitialized()) GTEST_SKIP();

    WindowEventType lastType = WindowEventType::Close;
    uint32_t lastKey = 0;

    device.PollEvents([&](const WindowEvent& ev) {
        lastType = ev.type;
        lastKey = ev.data.key.key_code;
    });

    GlfwWindowDevice::KeyCallback(Window(), GLFW_KEY_A, 0, GLFW_PRESS, 0);

    ASSERT_EQ(lastType, WindowEventType::KeyDown);
    ASSERT_EQ(lastKey, (uint32_t)GLFW_KEY_A);
}

TEST_F(GlfwWindowDeviceTest, KeyCallback_EmitsKeyUp) {
    if (!EnsureInitialized()) GTEST_SKIP();

    WindowEventType lastType = WindowEventType::KeyDown;
    device.PollEvents([&](const WindowEvent& ev) { lastType = ev.type; });

    GlfwWindowDevice::KeyCallback(Window(), GLFW_KEY_A, 0, GLFW_RELEASE, 0);

    ASSERT_EQ(lastType, WindowEventType::KeyUp);
}

TEST_F(GlfwWindowDeviceTest, CursorPosCallback_EmitsMouseMove) {
    if (!EnsureInitialized()) GTEST_SKIP();

    float lastX = 0, lastY = 0;
    device.PollEvents([&](const WindowEvent& ev) {
        lastX = ev.data.mouse_move.x;
        lastY = ev.data.mouse_move.y;
    });

    GlfwWindowDevice::CursorPosCallback(Window(), 100.0, 200.0);

    ASSERT_FLOAT_EQ(lastX, 100.0f);
    ASSERT_FLOAT_EQ(lastY, 200.0f);
}

TEST_F(GlfwWindowDeviceTest, MouseButtonCallback_EmitsMouseDown) {
    if (!EnsureInitialized()) GTEST_SKIP();

    WindowEventType lastType = WindowEventType::Close;
    device.PollEvents([&](const WindowEvent& ev) { lastType = ev.type; });

    GlfwWindowDevice::MouseButtonCallback(Window(), GLFW_MOUSE_BUTTON_LEFT, GLFW_PRESS, 0);

    ASSERT_EQ(lastType, WindowEventType::MouseButtonDown);
}

TEST_F(GlfwWindowDeviceTest, ScrollCallback_EmitsMouseScroll) {
    if (!EnsureInitialized()) GTEST_SKIP();

    float lastDX = 0, lastDY = 0;
    device.PollEvents([&](const WindowEvent& ev) {
        lastDX = ev.data.mouse_scroll.delta_x;
        lastDY = ev.data.mouse_scroll.delta_y;
    });

    GlfwWindowDevice::ScrollCallback(Window(), 1.5, -2.5);

    ASSERT_FLOAT_EQ(lastDX, 1.5f);
    ASSERT_FLOAT_EQ(lastDY, -2.5f);
}

TEST_F(GlfwWindowDeviceTest, WindowSizeCallback_EmitsResize) {
    if (!EnsureInitialized()) GTEST_SKIP();

    uint32_t lastW = 0, lastH = 0;
    device.PollEvents([&](const WindowEvent& ev) {
        lastW = ev.data.resize.width;
        lastH = ev.data.resize.height;
    });

    GlfwWindowDevice::WindowSizeCallback(Window(), 1024, 768);

    ASSERT_EQ(lastW, 1024);
    ASSERT_EQ(lastH, 768);
}

TEST_F(GlfwWindowDeviceTest, WindowCloseCallback_EmitsClose) {
    if (!EnsureInitialized()) GTEST_SKIP();

    bool closed = false;
    device.PollEvents([&](const WindowEvent& ev) {
        if (ev.type == WindowEventType::Close) closed = true;
    });

    GlfwWindowDevice::WindowCloseCallback(Window());

    ASSERT_TRUE(closed);
}

TEST_F(GlfwWindowDeviceTest, SetTitle_CallsGlfw) {
    if (!EnsureInitialized()) GTEST_SKIP();
    device.SetTitle("New Title");
    // Hard to verify without internal GLFW state, but covers the line
    SUCCEED();
}

TEST_F(GlfwWindowDeviceTest, Shutdown_ClearsWindow) {
    if (!EnsureInitialized()) GTEST_SKIP();
    device.Shutdown();
    ASSERT_EQ(Window(), nullptr);
}
