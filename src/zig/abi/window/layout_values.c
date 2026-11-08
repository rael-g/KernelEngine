#include <stddef.h>
#include <kernel_engine/window/window.h>
const unsigned long long layout_values[] = {
    sizeof(ke_window),
    offsetof(ke_window, handle),
    offsetof(ke_window, should_close),
    offsetof(ke_window, poll_events),
    offsetof(ke_window, get_size),
    offsetof(ke_window, get_native_handle),
    sizeof(ke_window_handle),
    offsetof(ke_window_handle, ref),
    offsetof(ke_window_handle, destroy),
    0,
};
