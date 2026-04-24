#pragma once

#include "window_types.hpp"
#include <functional>

namespace kernel_engine::window
{

/**
 * @brief Professional Hardware Abstraction Layer (HAL) for Windowing.
 * 100% independent of GLFW or OS-specific headers.
 */
class WindowDeviceInterface
{
public:
    virtual ~WindowDeviceInterface() = default;

    // ── Lifecycle ────────────────────────────────────────────────────────────
    virtual bool Initialize(const WindowConfig& config) = 0;
    virtual void Shutdown() = 0;
    
    /**
     * @brief Polls OS events and invokes the callback for each.
     */
    virtual void PollEvents(const std::function<void(const WindowEvent&)>& callback) = 0;
    
    virtual bool ShouldClose() const = 0;

    // ── State ────────────────────────────────────────────────────────────────
    virtual void SetTitle(const char* title) = 0;
    virtual void GetSize(uint32_t* width, uint32_t* height) const = 0;
    virtual void* GetNativeHandle() const = 0; // HWND, NSWindow*, etc.
};

} // namespace kernel_engine::window
