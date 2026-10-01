#ifndef KERNEL_ENGINE_INPUT_SNAPSHOT_H_
#define KERNEL_ENGINE_INPUT_SNAPSHOT_H_

#include <kernel_engine/common/types.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** Number of distinct key codes the snapshot bitsets address. */
#define KE_INPUT_MAX_KEYS 512

    /** 64-bit words needed to hold one bit per addressable key. */
#define KE_INPUT_KEY_WORDS (KE_INPUT_MAX_KEYS / 64)

    /** Number of mouse buttons the snapshot bitmasks address. */
#define KE_INPUT_MAX_MOUSE_BUTTONS 32

    /**
     * Frozen snapshot of all input state for a single frame.
     * Passed from the input poll to its readers so reads are consistent and thread-safe.
     *
     * The key fields are bitsets. Read them through the snapshot_is_* slots of ke_input rather
     * than indexing directly: the packing is a detail of this contract, and a
     * caller that reimplements it silently breaks if the packing ever changes.
     */
    typedef struct ke_input_snapshot
    {
        /** Bitset of keys currently held down. */
        uint64_t keys_down[KE_INPUT_KEY_WORDS];

        /** Bitset of keys that transitioned to down this frame. */
        uint64_t keys_pressed[KE_INPUT_KEY_WORDS];

        /** Bitset of keys that transitioned to up this frame. */
        uint64_t keys_released[KE_INPUT_KEY_WORDS];

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

#endif
