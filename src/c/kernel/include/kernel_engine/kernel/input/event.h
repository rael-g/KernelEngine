#ifndef KERNEL_ENGINE_KERNEL_INPUT_EVENT_H_
#define KERNEL_ENGINE_KERNEL_INPUT_EVENT_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Discriminator for ke_input_event.
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
     * @brief One discrete input event captured during ke.main's poll phase.
     *
     * Flat layout (no anonymous unions) for friction-free C# P/Invoke binding.
     * Field interpretation depends on @c kind:
     *   - KEY_DOWN / KEY_UP:           code = key code (GLFW codes)
     *   - MOUSE_BUTTON_DOWN/UP:        code = button index
     *   - MOUSE_MOVE:                  x, y = absolute cursor position
     *   - MOUSE_SCROLL:                x, y = scroll delta x, y
     */
    typedef struct ke_input_event
    {
        ke_input_event_kind kind;
        int32_t             code;
        float               x;
        float               y;
    } ke_input_event;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_INPUT_EVENT_H_
