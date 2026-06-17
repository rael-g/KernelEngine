#ifndef KERNEL_ENGINE_INPUT_INPUT_H_
#define KERNEL_ENGINE_INPUT_INPUT_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/input/input_export.h>
#include <kernel_engine/input/snapshot.h>
#include <kernel_engine/input/event.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_INPUT "ke_input"

    /// @brief System responsible for keyboard and mouse state tracking.
    typedef struct ke_input
    {
        void *handle;

        void (*destroy)(struct ke_input *self);

        /**
         * @brief Updates internal state (e.g. resets pressed/released flags).
         * Call once per main thread tick.
         */
        ke_result (*update)(struct ke_input *self, ke_error **out_error);

        bool (*is_key_pressed)(struct ke_input *self, int32_t key);
        bool (*is_key_released)(struct ke_input *self, int32_t key);
        bool (*is_key_down)(struct ke_input *self, int32_t key);

        /**
         * @brief Captures a frozen snapshot of the current input state.
         */
        void (*get_snapshot)(struct ke_input *self, ke_input_snapshot *out_snapshot);

        /**
         * @brief Drains pending discrete input events into @p out_buf and clears the queue.
         * Returns the number of events written (<= @p capacity). Excess events are dropped.
         * Must be called on ke.main (same thread as the on_* sinks).
         */
        uint32_t (*drain_events)(struct ke_input *self, ke_input_event *out_buf, uint32_t capacity);

        // ── Event Sinks (Main Thread Only) ────────────────────────────────────

        void (*on_key)(struct ke_input *self, int32_t key, int32_t action);
        void (*on_mouse_move)(struct ke_input *self, float x, float y);
        void (*on_mouse_button)(struct ke_input *self, int32_t button, int32_t action);
        void (*on_mouse_scroll)(struct ke_input *self, float dx, float dy);

    } ke_input;

    /// @brief Creates an input system.
    KE_INPUT_API ke_result ke_input_create(struct ke_logger *logger, ke_input **out_input, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_INPUT_INPUT_H_
