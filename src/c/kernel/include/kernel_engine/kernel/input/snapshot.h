#ifndef KERNEL_ENGINE_KERNEL_INPUT_SNAPSHOT_H_
#define KERNEL_ENGINE_KERNEL_INPUT_SNAPSHOT_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /**
     * @brief Frozen snapshot of all input state for a single frame.
     * Passed from ke.main to ke.sim to ensure thread-safe consistent reads.
     */
    typedef struct ke_input_snapshot
    {
        /// Bitset of keys currently held down.
        /// 512 keys / 64 bits = 8 uint64_t.
        uint64_t keys_down[8];

        /// Bitset of keys pressed THIS frame.
        uint64_t keys_pressed[8];

        /// Bitset of keys released THIS frame.
        uint64_t keys_released[8];

        float mouse_x;
        float mouse_y;
        float mouse_dx;
        float mouse_dy;
        float scroll_dx;
        float scroll_dy;

        uint32_t mouse_buttons_down;
        uint32_t mouse_buttons_pressed;
        uint32_t mouse_buttons_released;

    } ke_input_snapshot;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_INPUT_SNAPSHOT_H_
