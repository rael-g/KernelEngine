#pragma once

#include <kernel_engine/window/contract/window_export.h>
#include <cstdint>

namespace kernel_engine::window
{

// ── Configuration ────────────────────────────────────────────────────────────

struct WindowConfig
{
    const char* title;
    uint32_t    width;
    uint32_t    height;
    bool        fullscreen;
    bool        vsync;
};

// ── Events & Input ───────────────────────────────────────────────────────────

enum class WindowEventType : uint8_t
{
    Close,
    Resize,
    FocusGained,
    FocusLost,
    KeyDown,
    KeyUp,
    MouseMove,
    MouseButtonDown,
    MouseButtonUp,
    MouseScroll
};

struct WindowEvent
{
    WindowEventType type;
    union {
        struct { uint32_t width, height; } resize;
        struct { uint32_t key_code; bool alt, ctrl, shift; } key;
        struct { float x, y; } mouse_move;
        struct { uint8_t button; float x, y; } mouse_button;
        struct { float delta_x, delta_y; } mouse_scroll;
    } data;
};

} // namespace kernel_engine::window
