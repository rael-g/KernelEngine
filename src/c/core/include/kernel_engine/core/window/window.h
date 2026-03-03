#pragma once

#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/types.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_WINDOW "ke_window"

    /// @brief OS-level window abstraction.
    typedef struct ke_window
    {
        void *handle;
        void (*destroy)(struct ke_window *self);

        bool (*should_close)(struct ke_window *self);
        ke_result (*poll_events)(struct ke_window *self);
        ke_result (*swap_buffers)(struct ke_window *self);
        ke_result (*get_size)(struct ke_window *self, int *width, int *height);
        void *(*get_native_handle)(struct ke_window *self);
    } ke_window;

#ifdef __cplusplus
}
#endif
