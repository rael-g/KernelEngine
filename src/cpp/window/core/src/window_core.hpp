#pragma once

#include <kernel_engine/kernel/window/window.h>
#include <window_device.hpp>
#include <window_export.h>
#include <memory>

namespace kernel_engine::window
{

/**
 * @brief High-level agnostic window controller.
 * Handles the logic of events, input state, and OS integration via HAL.
 */
class KE_WINDOW_API WindowCore
{
public:
    WindowCore();
    ~WindowCore();

    ke_result Initialize(const WindowConfig& config);
    void Shutdown();
    void PollEvents();
    bool ShouldClose() const;

    void SetTitle(const char* title);
    ke_result GetSize(uint32_t* width, uint32_t* height) const;
    void* GetNativeHandle() const;

    ke_window* ToApi();

    // Dependency Injection
    void SetDevice(WindowDevice* device);

private:
    void HandleEvent(const WindowEvent& ev);

    WindowDevice* device_ = nullptr;
    bool own_device_ = false;
    bool initialized_ = false;

    ke_window api_struct_{};
};

} // namespace kernel_engine::window
