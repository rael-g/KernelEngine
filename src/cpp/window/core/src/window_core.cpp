#include <window_core.hpp>
#include <kernel_engine/common/error.h>
#include <cstring>

namespace kernel_engine::window
{

WindowCore::WindowCore()
{
    std::memset(&api_struct_, 0, sizeof(api_struct_));
    api_struct_.handle = this;
    api_struct_.on_initialize = [](ke_window* self, ke_error** out_error) {
        if (!self) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        auto* core = static_cast<WindowCore*>(self->handle);
        // Initialization usually happens via WindowCore::Initialize() directly
        // but we can call it here if we store config.
        (void)core;
        return KE_OK;
    };
    api_struct_.on_shutdown = [](ke_window* self, ke_error** out_error) {
        if (!self) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        static_cast<WindowCore*>(self->handle)->Shutdown();
        return KE_OK;
    };
    api_struct_.should_close = [](ke_window* self) -> ke_bool {
        if (!self) return 1;
        return static_cast<WindowCore*>(self->handle)->ShouldClose() ? 1 : 0;
    };
    api_struct_.poll_events = [](ke_window* self, ke_error** out_error) {
        if (!self) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        static_cast<WindowCore*>(self->handle)->PollEvents();
        return KE_OK;
    };
    api_struct_.get_size = [](ke_window* self, int32_t* w, int32_t* h, ke_error** out_error) {
        if (!self) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        uint32_t uw, uh;
        auto res = static_cast<WindowCore*>(self->handle)->GetSize(&uw, &uh);
        if (w) *w = (int32_t)uw;
        if (h) *h = (int32_t)uh;
        return res;
    };
    api_struct_.get_native_handle = [](ke_window* self) {
        if (!self) return (void*)nullptr;
        return static_cast<WindowCore*>(self->handle)->GetNativeHandle();
    };
}

WindowCore::~WindowCore()
{
    Shutdown();
}

ke_result WindowCore::Initialize(const WindowConfig& config)
{
    if (!device_) return KE_ERROR;
    if (initialized_) return KE_OK;

    if (!device_->Initialize(config)) return KE_ERROR;

    initialized_ = true;
    return KE_OK;
}

void WindowCore::Shutdown()
{
    if (device_) {
        device_->Shutdown();
    }
    if (own_device_) {
        delete device_;
        device_ = nullptr;
    }
    initialized_ = false;
}

void WindowCore::PollEvents()
{
    if (device_) {
        device_->PollEvents([this](const WindowEvent& ev) {
            HandleEvent(ev);
        });
    }
}

bool WindowCore::ShouldClose() const
{
    return device_ ? device_->ShouldClose() : true;
}

void WindowCore::SetTitle(const char* title)
{
    if (device_) device_->SetTitle(title);
}

ke_result WindowCore::GetSize(uint32_t* width, uint32_t* height) const
{
    if (!device_) return KE_ERROR;
    device_->GetSize(width, height);
    return KE_OK;
}

void* WindowCore::GetNativeHandle() const
{
    return device_ ? device_->GetNativeHandle() : nullptr;
}

ke_window* WindowCore::ToApi()
{
    return &api_struct_;
}

void WindowCore::DestroyApi(ke_window* self)
{
    if (!self) return;
    auto* core = static_cast<WindowCore*>(self->handle);
    delete core;
}

void WindowCore::SetDevice(WindowDevice* device)
{
    if (own_device_) delete device_;
    device_ = device;
    own_device_ = false;
}

void WindowCore::SetInput(ke_input* input)
{
    input_ = input;
}

void WindowCore::HandleEvent(const WindowEvent& ev)
{
    if (!input_) return;
    if (ev.type == WindowEventType::KeyDown || ev.type == WindowEventType::KeyUp)
    {
        int action = (ev.type == WindowEventType::KeyDown) ? 1 : 0;
        input_->on_key(input_, (int32_t)ev.data.key.key_code, action);
    }
    else if (ev.type == WindowEventType::MouseMove)
    {
        input_->on_mouse_move(input_, ev.data.mouse_move.x, ev.data.mouse_move.y);
    }
    else if (ev.type == WindowEventType::MouseButtonDown || ev.type == WindowEventType::MouseButtonUp)
    {
        int action = (ev.type == WindowEventType::MouseButtonDown) ? 1 : 0;
        input_->on_mouse_button(input_, (int32_t)ev.data.mouse_button.button, action);
    }
    else if (ev.type == WindowEventType::MouseScroll)
    {
        input_->on_mouse_scroll(input_, ev.data.mouse_scroll.delta_x, ev.data.mouse_scroll.delta_y);
    }
}

} // namespace kernel_engine::window
