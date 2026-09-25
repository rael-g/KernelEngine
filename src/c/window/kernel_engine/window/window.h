#ifndef KERNEL_ENGINE_WINDOW_WINDOW_H_
#define KERNEL_ENGINE_WINDOW_WINDOW_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>

#include <kernel_engine/common/types.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_WINDOW "ke_window"

    /** [interface] OS-level window abstraction. */
    typedef struct ke_window
    {
        void *handle;

        /** [lifecycle:init] Performs backend-specific setup, right after creation. */
        bool (*on_initialize)(struct ke_window *self, ke_error **out_error);

        /** [lifecycle:shutdown] Performs backend-specific teardown, right before destroy. */
        bool (*on_shutdown)(struct ke_window *self, ke_error **out_error);

        /** Returns true once the user has requested the window to close. */
        ke_bool (*should_close)(struct ke_window *self);

        /** Processes pending OS events. Call once per frame. */
        bool (*poll_events)(struct ke_window *self, ke_error **out_error);

        /** Presents the back buffer. Call once per frame, after rendering. */
        bool (*swap_buffers)(struct ke_window *self, ke_error **out_error);

        /**
         * Retrieves the current client-area size in pixels.
         * @param width  [out] Receives the client-area width.
         * @param height [out] Receives the client-area height.
         */
        bool (*get_size)(struct ke_window *self, int32_t *width, int32_t *height, ke_error **out_error);

        /** Returns the platform-specific native handle (HWND, X11 Window, ...). */
        void *(*get_native_handle)(struct ke_window *self);
    } ke_window;

    typedef struct ke_window_handle
    {
        ke_window *ref;
        void (*destroy)(ke_window *self);
    } ke_window_handle;

#ifdef __cplusplus
}
#endif

#endif
