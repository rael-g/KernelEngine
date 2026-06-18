#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/allocator/allocator.h>
#include <window_core.hpp>
#include <window_device.hpp>

using namespace kernel_engine::window;
using ::testing::Return;
using ::testing::_;
using ::testing::NiceMock;

// ── Mock ─────────────────────────────────────────────────────────────────────

class MockWindowDevice : public WindowDevice {
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
            WindowCore::DestroyApi(window);  // deletes core
            window = nullptr;
        }
        delete mock_device;
        mock_device = nullptr;
    }
};

// ── Factory null-param tests ──────────────────────────────────────────────────

TEST(WindowFactoryTest, Create_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_window_glfw_create(nullptr, nullptr, nullptr), KE_ERROR);
}

TEST(WindowFactoryTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_window_handle w{};
    ASSERT_EQ(ke_window_glfw_create(nullptr, &w, nullptr), KE_ERROR);
}

TEST(WindowFactoryTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_window_handle w{};
    ke_window_glfw_params params = { nullptr, nullptr, nullptr, "Test", 800, 600, 0 };
    ASSERT_EQ(ke_window_glfw_create(&params, &w, nullptr), KE_ERROR);
}

TEST(WindowFactoryTest, Create_Success_OrWindowError) {
    ke_allocator alloc{};
    alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
    alloc.free = [](ke_allocator*, void* p) { std::free(p); };

    ke_window_glfw_params params = { &alloc, nullptr, nullptr, "Test", 800, 600, 0 };
    ke_window_handle w{};
    ke_result res = ke_window_glfw_create(&params, &w, nullptr);
    if (res == KE_OK) {
        w.destroy(w.ref);
    }
    ASSERT_TRUE(res == KE_OK || res == KE_ERROR);
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
    window->get_size(window, &w, &h, NULL);
    ASSERT_EQ(w, 800);
    ASSERT_EQ(h, 600);
}

TEST_F(WindowCoreTest, PollEvents_DelegatesToDevice) {
    EXPECT_CALL(*mock_device, PollEvents(_)).Times(1);
    ASSERT_EQ(window->poll_events(window, NULL), KE_OK);
}

TEST_F(WindowCoreTest, Shutdown_CallsDeviceShutdown) {
    EXPECT_CALL(*mock_device, Shutdown()).Times(::testing::AtLeast(1));
    window->on_shutdown(window, NULL);
}

TEST_F(WindowCoreTest, Initialize_ReturnsError_WhenDeviceFails) {
    EXPECT_CALL(*mock_device, Initialize(_)).WillOnce(Return(false));
    WindowConfig config = { "Fail", 800, 600, false, true };
    ASSERT_EQ(core->Initialize(config), KE_ERROR);
}

TEST_F(WindowCoreTest, Initialize_ReturnsOk_WhenAlreadyInitialized) {
    EXPECT_CALL(*mock_device, Initialize(_)).WillOnce(Return(true));
    WindowConfig config = { "Ok", 800, 600, false, true };
    core->Initialize(config);
    ASSERT_EQ(core->Initialize(config), KE_OK); // Should return KE_OK immediately
}

TEST_F(WindowCoreTest, SetTitle_DelegatesToDevice) {
    EXPECT_CALL(*mock_device, SetTitle(::testing::StrEq("Test Title"))).Times(1);
    core->SetTitle("Test Title");
}

TEST_F(WindowCoreTest, HandleEvent_KeyDown_UpdatesInput) {
    struct MockInput {
        static void OnKey(ke_input* self, int32_t key, int action) {
            auto* last_key = static_cast<int32_t*>(self->handle);
            *last_key = key;
        }
    };
    int32_t last_key = 0;
    ke_input input_api{};
    input_api.handle = &last_key;
    input_api.on_key = MockInput::OnKey;
    core->SetInput(&input_api);

    // Simulate event from device
    ON_CALL(*mock_device, PollEvents(_)).WillByDefault(::testing::Invoke([](const std::function<void(const WindowEvent&)>& callback) {
        WindowEvent ev{};
        ev.type = WindowEventType::KeyDown;
        ev.data.key.key_code = 42;
        callback(ev);
    }));

    window->poll_events(window, NULL);
    ASSERT_EQ(last_key, 42);
}

TEST_F(WindowCoreTest, HandleEvent_MouseMove_UpdatesInput) {
    struct MockInput {
        static void OnMouseMove(ke_input* self, float x, float y) {
            auto* last_pos = static_cast<float*>(self->handle);
            last_pos[0] = x;
            last_pos[1] = y;
        }
    };
    float last_pos[2] = {0, 0};
    ke_input input_api{};
    input_api.handle = last_pos;
    input_api.on_mouse_move = MockInput::OnMouseMove;
    core->SetInput(&input_api);

    ON_CALL(*mock_device, PollEvents(_)).WillByDefault(::testing::Invoke([](const std::function<void(const WindowEvent&)>& callback) {
        WindowEvent ev{};
        ev.type = WindowEventType::MouseMove;
        ev.data.mouse_move.x = 10.5f;
        ev.data.mouse_move.y = 20.5f;
        callback(ev);
    }));

    window->poll_events(window, NULL);
    ASSERT_FLOAT_EQ(last_pos[0], 10.5f);
    ASSERT_FLOAT_EQ(last_pos[1], 20.5f);
}

TEST_F(WindowCoreTest, HandleEvent_MouseButton_UpdatesInput) {
    struct MockInput {
        static void OnMouseButton(ke_input* self, int32_t button, int action) {
            auto* last_btn = static_cast<int32_t*>(self->handle);
            *last_btn = button;
        }
    };
    int32_t last_btn = -1;
    ke_input input_api{};
    input_api.handle = &last_btn;
    input_api.on_mouse_button = MockInput::OnMouseButton;
    core->SetInput(&input_api);

    ON_CALL(*mock_device, PollEvents(_)).WillByDefault(::testing::Invoke([](const std::function<void(const WindowEvent&)>& callback) {
        WindowEvent ev{};
        ev.type = WindowEventType::MouseButtonDown;
        ev.data.mouse_button.button = 1;
        callback(ev);
    }));

    window->poll_events(window, NULL);
    ASSERT_EQ(last_btn, 1);
}

TEST_F(WindowCoreTest, HandleEvent_MouseUp_UpdatesInput) {
    struct MockInput {
        static void OnMouseButton(ke_input* self, int32_t button, int action) {
            auto* last_action = static_cast<int*>(self->handle);
            *last_action = action;
        }
    };
    int last_action = -1;
    ke_input input_api{};
    input_api.handle = &last_action;
    input_api.on_mouse_button = MockInput::OnMouseButton;
    core->SetInput(&input_api);

    ON_CALL(*mock_device, PollEvents(_)).WillByDefault(::testing::Invoke([](const std::function<void(const WindowEvent&)>& callback) {
        WindowEvent ev{};
        ev.type = WindowEventType::MouseButtonUp;
        ev.data.mouse_button.button = 0;
        callback(ev);
    }));

    window->poll_events(window, NULL);
    ASSERT_EQ(last_action, 0); // 0 for Up
}

TEST_F(WindowCoreTest, HandleEvent_KeyUp_UpdatesInput) {
    struct MockInput {
        static void OnKey(ke_input* self, int32_t key, int action) {
            auto* last_action = static_cast<int*>(self->handle);
            *last_action = action;
        }
    };
    int last_action = -1;
    ke_input input_api{};
    input_api.handle = &last_action;
    input_api.on_key = MockInput::OnKey;
    core->SetInput(&input_api);

    ON_CALL(*mock_device, PollEvents(_)).WillByDefault(::testing::Invoke([](const std::function<void(const WindowEvent&)>& callback) {
        WindowEvent ev{};
        ev.type = WindowEventType::KeyUp;
        ev.data.key.key_code = 1;
        callback(ev);
    }));

    window->poll_events(window, NULL);
    ASSERT_EQ(last_action, 0); // 0 for Up
}

TEST_F(WindowCoreTest, API_PollEvents_NullSelf_ReturnsInvalidArgument) {
    ASSERT_EQ(window->poll_events(nullptr, NULL), KE_ERROR);
}

TEST_F(WindowCoreTest, API_ShouldClose_NullSelf_ReturnsTrue) {
    ASSERT_TRUE(window->should_close(nullptr));
}

TEST_F(WindowCoreTest, API_GetNativeHandle_NullSelf_ReturnsNull) {
    ASSERT_EQ(window->get_native_handle(nullptr), nullptr);
}

TEST_F(WindowCoreTest, API_GetSize_NullSelf_ReturnsInvalidArgument) {
    ASSERT_EQ(window->get_size(nullptr, nullptr, nullptr, NULL), KE_ERROR);
}

TEST_F(WindowCoreTest, Destroy_NullSelf_IsSafe) {
    auto d = &WindowCore::DestroyApi;
    WindowCore::DestroyApi(window);
    window = nullptr;
    d(nullptr);
}
