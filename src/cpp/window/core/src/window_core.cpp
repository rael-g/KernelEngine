#include <window_core.hpp>
#include <kernel_engine/kernel/input/input_messages.h>
#include <cstring>

namespace kernel_engine::window
{

WindowCore::WindowCore()
{
    std::memset(&api_struct_, 0, sizeof(api_struct_));
    api_struct_.handle = this;

    api_struct_.on_initialize = [](ke_window* self) {
        // Core initialization is usually driven by the Factory, 
        // but we can map C-API calls here if needed.
        return KE_OK; 
    };

    api_struct_.on_shutdown = [](ke_window* self) {
        static_cast<WindowCore*>(self->handle)->Shutdown();
        return KE_OK;
    };

    api_struct_.poll_events = [](ke_window* self) {
        static_cast<WindowCore*>(self->handle)->PollEvents();
        return KE_OK;
    };

    api_struct_.should_close = [](ke_window* self) {
        return (ke_bool)static_cast<WindowCore*>(self->handle)->ShouldClose();
    };

    api_struct_.get_native_handle = [](ke_window* self) {
        return static_cast<WindowCore*>(self->handle)->GetNativeHandle();
    };

    api_struct_.get_size = [](ke_window* self, int32_t* w, int32_t* h) {
        uint32_t uw, uh;
        auto res = static_cast<WindowCore*>(self->handle)->GetSize(&uw, &uh);
        if (w) *w = (int32_t)uw;
        if (h) *h = (int32_t)uh;
        return res;
    };

    api_struct_.destroy = [](ke_window* self) {
        auto* core = static_cast<WindowCore*>(self->handle);
        delete core;
    };
}

WindowCore::~WindowCore()
{
    Shutdown();
}

void WindowCore::SetDevice(WindowDevice* device)
{
    if (own_device_ && device_) delete device_;
    device_ = device;
    own_device_ = false;
}

void WindowCore::SetPipe(ke_message_pipe* pipe)
{
    pipe_ = pipe;
}

ke_result WindowCore::Initialize(const WindowConfig& config)
{
    if (!device_) return KE_ERROR_NOT_INITIALIZED;
    if (!device_->Initialize(config)) return KE_ERROR_WINDOW;
    initialized_ = true;
    return KE_OK;
}

void WindowCore::Shutdown()
{
    if (device_) device_->Shutdown();
    initialized_ = false;
}

void WindowCore::PollEvents()
{
    if (device_) {
        device_->PollEvents([this](const WindowEvent& ev) {
            this->HandleEvent(ev);
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
    if (!device_) return KE_ERROR_NOT_INITIALIZED;
    device_->GetSize(width, height);
    return KE_OK;
}

void* WindowCore::GetNativeHandle() const
{
    return device_ ? device_->GetNativeHandle() : nullptr;
}

ke_window* WindowCore::ToApi() { return &api_struct_; }

void WindowCore::HandleEvent(const WindowEvent& ev)
{
    if (!pipe_) return;
    if (ev.type == WindowEventType::KeyDown || ev.type == WindowEventType::KeyUp)
    {
        int action = (ev.type == WindowEventType::KeyDown) ? 1 : 0;
        ke_msg_key_event msg = {(int32_t)ev.data.key.key_code, action};
        pipe_->broadcast(pipe_, KE_MSG_KEY_EVENT, &msg, sizeof(msg));
    }
}

} // namespace kernel_engine::window
