#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <window_core.hpp>
#include <window_device.hpp>

using namespace kernel_engine::window;
using ::testing::Return;
using ::testing::_;
using ::testing::NiceMock;

// ── Mock ─────────────────────────────────────────────────────────────────────

class MockWindowDevice : public WindowDeviceInterface {
public:
    MOCK_METHOD(bool, Initialize, (const WindowConfig&), (override));
    MOCK_METHOD(void, Shutdown, (), (override));
    MOCK_METHOD(void, PollEvents, (const std::function<void(const WindowEvent&)>&), (override));
    MOCK_METHOD(bool, ShouldClose, (), (const, override));
    MOCK_METHOD(void, SetTitle, (const char*), (override));
    MOCK_METHOD(void, GetSize, (uint32_t*, uint32_t*), (const, override));
    MOCK_METHOD(void*, GetNativeHandle, (), (const, override));
};

// ── Fixture ───────────────────────────────────────────────────────────────────

class WindowCoreTest : public ::testing::Test {
protected:
    ke_window* window = nullptr;
    NiceMock<MockWindowDevice>* mock_device = nullptr;
    WindowCore* core = nullptr;

    void SetUp() override {
        mock_device = new NiceMock<MockWindowDevice>();
        core = new WindowCore();
        core->SetDevice(mock_device);
        window = core->ToApi();
    }

    void TearDown() override {
        if (window) {
            window->destroy(window);
            window = nullptr;
        }
        delete mock_device;
        mock_device = nullptr;
    }
};

// ── Factory null-param tests ──────────────────────────────────────────────────

TEST(WindowFactoryTest, Create_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_window_glfw_create(nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST(WindowFactoryTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_window* w = nullptr;
    ASSERT_EQ(ke_window_glfw_create(nullptr, &w), KE_ERROR_INVALID_ARGUMENT);
}

TEST(WindowFactoryTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_window* w = nullptr;
    ke_window_glfw_params params = { nullptr, nullptr, "Test", 800, 600, 0 };
    ASSERT_EQ(ke_window_glfw_create(&params, &w), KE_ERROR_INVALID_ARGUMENT);
}

// ── Core unit tests via mock device ──────────────────────────────────────────

TEST_F(WindowCoreTest, ToApi_ReturnsValidPointer) {
    ASSERT_NE(window, nullptr);
}

TEST_F(WindowCoreTest, ShouldClose_BeforeInit_ReturnsTrue) {
    ON_CALL(*mock_device, ShouldClose()).WillByDefault(Return(true));
    ASSERT_TRUE(window->should_close(window));
}

TEST_F(WindowCoreTest, ShouldClose_WhenDeviceReturnsFalse) {
    ON_CALL(*mock_device, ShouldClose()).WillByDefault(Return(false));
    ASSERT_FALSE(window->should_close(window));
}

TEST_F(WindowCoreTest, GetNativeHandle_DelegatesToDevice) {
    ON_CALL(*mock_device, GetNativeHandle()).WillByDefault(Return((void*)0x1234));
    ASSERT_EQ(window->get_native_handle(window), (void*)0x1234);
}

TEST_F(WindowCoreTest, GetNativeHandle_BeforeInit_ReturnsNull) {
    ON_CALL(*mock_device, GetNativeHandle()).WillByDefault(Return(nullptr));
    ASSERT_EQ(window->get_native_handle(window), nullptr);
}

TEST_F(WindowCoreTest, GetSize_DelegatesToDevice) {
    ON_CALL(*mock_device, GetSize(_, _))
        .WillByDefault(::testing::Invoke([](uint32_t* w, uint32_t* h) {
            if (w) *w = 800;
            if (h) *h = 600;
        }));
    int32_t w = 0, h = 0;
    window->get_size(window, &w, &h);
    ASSERT_EQ(w, 800);
    ASSERT_EQ(h, 600);
}

TEST_F(WindowCoreTest, PollEvents_DelegatesToDevice) {
    EXPECT_CALL(*mock_device, PollEvents(_)).Times(1);
    ASSERT_EQ(window->poll_events(window), KE_OK);
}

TEST_F(WindowCoreTest, Shutdown_CallsDeviceShutdown) {
    EXPECT_CALL(*mock_device, Shutdown()).Times(::testing::AtLeast(1));
    window->on_shutdown(window);
}

TEST_F(WindowCoreTest, Destroy_Works) {
    window->destroy(window);
    window = nullptr;
    SUCCEED();
}
