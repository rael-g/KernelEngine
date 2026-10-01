#ifndef KERNEL_ENGINE_INPUT_INPUT_H_
#define KERNEL_ENGINE_INPUT_INPUT_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/types.h>
#include <kernel_engine/input/snapshot.h>
#include <kernel_engine/input/event.h>
#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_logger;

    /** Live keyboard and mouse state for one window. */
    typedef struct ke_input
    {
        void *handle;

        /**
         * Updates internal state, clearing this frame's pressed/released edges.
         * Call once per tick, before any query.
         */
        bool (*update)(struct ke_input *self, ke_error **out_error);

        /**
         * Returns true if the key transitioned to down during this tick.
         * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
         */
        ke_bool (*is_key_pressed)(struct ke_input *self, int32_t key);

        /**
         * Returns true if the key transitioned to up during this tick.
         * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
         */
        ke_bool (*is_key_released)(struct ke_input *self, int32_t key);

        /**
         * Returns true while the key is held down.
         * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
         */
        ke_bool (*is_key_down)(struct ke_input *self, int32_t key);

        /**
         * Captures a frozen copy of the current state, safe to read from another
         * thread while this instance keeps updating.
         * @param out_snapshot [out] Receives the snapshot.
         */
        void (*get_snapshot)(struct ke_input *self, ke_input_snapshot *out_snapshot);

        /**
         * Returns true while the key is held down in a snapshot.
         * @param snapshot [borrowed] Snapshot to read.
         * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
         */
        ke_bool (*snapshot_is_key_down)(struct ke_input *self, const ke_input_snapshot *snapshot, int32_t key);

        /**
         * Returns true if the key transitioned to down during the snapshot's frame.
         * @param snapshot [borrowed] Snapshot to read.
         * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
         */
        ke_bool (*snapshot_is_key_pressed)(struct ke_input *self, const ke_input_snapshot *snapshot, int32_t key);

        /**
         * Returns true if the key transitioned to up during the snapshot's frame.
         * @param snapshot [borrowed] Snapshot to read.
         * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
         */
        ke_bool (*snapshot_is_key_released)(struct ke_input *self, const ke_input_snapshot *snapshot, int32_t key);

        /**
         * Returns true while the mouse button is held down in a snapshot.
         * @param snapshot [borrowed] Snapshot to read.
         * @param button [enum:ke_mouse_button] Button to query. Out-of-range indices read as false.
         */
        ke_bool (*snapshot_is_mouse_button_down)(struct ke_input *self, const ke_input_snapshot *snapshot, int32_t button);

        /**
         * Returns true if the mouse button transitioned to down during the snapshot's frame.
         * @param snapshot [borrowed] Snapshot to read.
         * @param button [enum:ke_mouse_button] Button to query. Out-of-range indices read as false.
         */
        ke_bool (*snapshot_is_mouse_button_pressed)(struct ke_input *self, const ke_input_snapshot *snapshot, int32_t button);

        /**
         * Returns true if the mouse button transitioned to up during the snapshot's frame.
         * @param snapshot [borrowed] Snapshot to read.
         * @param button [enum:ke_mouse_button] Button to query. Out-of-range indices read as false.
         */
        ke_bool (*snapshot_is_mouse_button_released)(struct ke_input *self, const ke_input_snapshot *snapshot, int32_t button);

        /**
         * [raw] Drains pending discrete events and clears the queue. Events beyond the
         * buffer capacity are dropped. Must run on the same thread as the sinks below.
         * @param out_buf [out,array_of:capacity] Receives the drained events.
         * @param capacity Maximum number of events to write.
         * @return Number of events written.
         */
        uint32_t (*drain_events)(struct ke_input *self, ke_input_event *out_buf, uint32_t capacity);

        /**
         * [sink] Reports a key transition from the window backend.
         * @param key [enum:ke_key] Key that changed.
         * @param action [enum:ke_input_action] Whether the key went down or up.
         */
        void (*on_key)(struct ke_input *self, int32_t key, int32_t action);

        /**
         * [sink] Reports an absolute cursor position from the window backend.
         * @param x Cursor position on the horizontal axis, in pixels.
         * @param y Cursor position on the vertical axis, in pixels.
         */
        void (*on_mouse_move)(struct ke_input *self, float x, float y);

        /**
         * [sink] Reports a mouse-button transition from the window backend.
         * @param button [enum:ke_mouse_button] Button that changed.
         * @param action [enum:ke_input_action] Whether the button went down or up.
         */
        void (*on_mouse_button)(struct ke_input *self, int32_t button, int32_t action);

        /**
         * [sink] Reports a scroll-wheel delta from the window backend.
         * @param dx Horizontal scroll delta.
         * @param dy Vertical scroll delta.
         */
        void (*on_mouse_scroll)(struct ke_input *self, float dx, float dy);

    } ke_input;

    typedef struct ke_input_handle
    {
        ke_input *ref;
        void (*destroy)(ke_input *self);
    } ke_input_handle;

#ifdef __cplusplus
}
#endif

#endif
