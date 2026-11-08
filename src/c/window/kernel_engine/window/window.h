#ifndef KERNEL_ENGINE_WINDOW_WINDOW_H_
#define KERNEL_ENGINE_WINDOW_WINDOW_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/result/result.h>

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** [interface] OS-level window abstraction. */
    typedef struct ke_window
    {
        void *handle;

        /** Returns true once the user has requested the window to close. */
        bool (*should_close)(struct ke_window *self);

        /** Processes pending OS events. Call once per frame. */
        void (*poll_events)(struct ke_window *self);

        /**
         * Retrieves the current client-area size in pixels.
         * @param width  [out] Receives the client-area width.
         * @param height [out] Receives the client-area height.
         */
        void (*get_size)(struct ke_window *self, int32_t *width, int32_t *height);

        /** Returns the platform-specific native window handle. */
        void *(*get_native_handle)(struct ke_window *self);
    } ke_window;

    /// [owner]
    typedef struct ke_window_handle
    {
        ke_window *ref;
        void (*destroy)(ke_window *self);
    } ke_window_handle;

#ifdef __cplusplus
}
#endif

#endif
