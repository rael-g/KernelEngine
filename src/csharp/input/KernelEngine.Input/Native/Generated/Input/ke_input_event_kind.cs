using KernelEngine.Common.Native;

namespace KernelEngine.Input.Native;

public enum ke_input_event_kind
{
    KE_INPUT_EVENT_NONE = 0,
    KE_INPUT_EVENT_KEY_DOWN = 1,
    KE_INPUT_EVENT_KEY_UP = 2,
    KE_INPUT_EVENT_MOUSE_BUTTON_DOWN = 3,
    KE_INPUT_EVENT_MOUSE_BUTTON_UP = 4,
    KE_INPUT_EVENT_MOUSE_MOVE = 5,
    KE_INPUT_EVENT_MOUSE_SCROLL = 6,
}
