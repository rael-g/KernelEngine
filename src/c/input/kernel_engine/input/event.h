#ifndef KERNEL_ENGINE_INPUT_EVENT_H_
#define KERNEL_ENGINE_INPUT_EVENT_H_

#include <stdbool.h>
#include <stdint.h>

#include <kernel_engine/input/key.h>
#include <kernel_engine/math/math.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /**
     * Direction of a key or mouse-button transition.
     */
    typedef enum ke_input_action
    {
        KE_INPUT_ACTION_RELEASE = 0,
        KE_INPUT_ACTION_PRESS   = 1,
    } ke_input_action;

    /** Discriminator for ke_input_event. */
    typedef enum ke_input_event_kind
    {
        KE_INPUT_EVENT_NONE               = 0,
        KE_INPUT_EVENT_KEY_DOWN           = 1,
        KE_INPUT_EVENT_KEY_UP             = 2,
        KE_INPUT_EVENT_MOUSE_BUTTON_DOWN  = 3,
        KE_INPUT_EVENT_MOUSE_BUTTON_UP    = 4,
        KE_INPUT_EVENT_MOUSE_MOVE         = 5,
        KE_INPUT_EVENT_MOUSE_SCROLL       = 6,
    } ke_input_event_kind;

    /**
     * @brief One discrete input event captured during the input poll.
     *
     * Field meaning depends on @c kind:
     *   - KEY_DOWN / KEY_UP:           key
     *   - MOUSE_BUTTON_DOWN/UP:        button
     *   - MOUSE_MOVE:                  position, the absolute cursor position
     *   - MOUSE_SCROLL:                scroll, the wheel delta
     * A handler sets @c handled to stop further propagation.
     */
    typedef struct ke_input_event
    {
        ke_input_event_kind kind;
        ke_key              key;
        ke_mouse_button     button;
        ke_vec2             scroll;
        ke_vec2             position;
        bool                handled;
    } ke_input_event;

#ifdef __cplusplus
}
#endif

#endif
