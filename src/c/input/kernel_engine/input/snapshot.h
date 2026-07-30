#ifndef KERNEL_ENGINE_INPUT_SNAPSHOT_H_
#define KERNEL_ENGINE_INPUT_SNAPSHOT_H_

#include <kernel_engine/common/types.h>
#include <kernel_engine/input/input_export.h>
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
     * Passed from ke.main to ke.sim so reads are consistent and thread-safe.
     *
     * The key fields are bitsets. Read them through the accessors below rather
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

    /**
     * Returns true while the key is held down.
     * @param snapshot [borrowed] Snapshot to read.
     * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
     */
    KE_INPUT_API ke_bool ke_input_snapshot_is_key_down(const ke_input_snapshot *snapshot, int32_t key);

    /**
     * Returns true if the key transitioned to down during the snapshot's frame.
     * @param snapshot [borrowed] Snapshot to read.
     * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
     */
    KE_INPUT_API ke_bool ke_input_snapshot_is_key_pressed(const ke_input_snapshot *snapshot, int32_t key);

    /**
     * Returns true if the key transitioned to up during the snapshot's frame.
     * @param snapshot [borrowed] Snapshot to read.
     * @param key [enum:ke_key] Key to query. Out-of-range codes read as false.
     */
    KE_INPUT_API ke_bool ke_input_snapshot_is_key_released(const ke_input_snapshot *snapshot, int32_t key);

    /**
     * Returns true while the mouse button is held down.
     * @param snapshot [borrowed] Snapshot to read.
     * @param button [enum:ke_mouse_button] Button to query. Out-of-range indices read as false.
     */
    KE_INPUT_API ke_bool ke_input_snapshot_is_mouse_button_down(const ke_input_snapshot *snapshot, int32_t button);

    /**
     * Returns true if the mouse button transitioned to down during the snapshot's frame.
     * @param snapshot [borrowed] Snapshot to read.
     * @param button [enum:ke_mouse_button] Button to query. Out-of-range indices read as false.
     */
    KE_INPUT_API ke_bool ke_input_snapshot_is_mouse_button_pressed(const ke_input_snapshot *snapshot, int32_t button);

    /**
     * Returns true if the mouse button transitioned to up during the snapshot's frame.
     * @param snapshot [borrowed] Snapshot to read.
     * @param button [enum:ke_mouse_button] Button to query. Out-of-range indices read as false.
     */
    KE_INPUT_API ke_bool ke_input_snapshot_is_mouse_button_released(const ke_input_snapshot *snapshot, int32_t button);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_INPUT_SNAPSHOT_H_
