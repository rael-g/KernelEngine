#ifndef KERNEL_ENGINE_WINDOW_WINDOW_H_
#define KERNEL_ENGINE_WINDOW_WINDOW_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>

#define KE_ERROR_WINDOW ((ke_result)-200)
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

        ke_result (*on_initialize)(struct ke_window *self);
        ke_result (*on_shutdown)(struct ke_window *self);

        bool (*should_close)(struct ke_window *self);
        ke_result (*poll_events)(struct ke_window *self);
        ke_result (*swap_buffers)(struct ke_window *self);
        ke_result (*get_size)(struct ke_window *self, int32_t *width, int32_t *height);
        void *(*get_native_handle)(struct ke_window *self);
    } ke_window;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_WINDOW_WINDOW_H_
