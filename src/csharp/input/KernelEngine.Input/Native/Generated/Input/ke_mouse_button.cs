using KernelEngine.Common.Native;

namespace KernelEngine.Input.Native;

[NativeTypeName("unsigned int")]
public enum ke_mouse_button : uint
{
    KE_MOUSE_BUTTON_1 = 0,
    KE_MOUSE_BUTTON_2 = 1,
    KE_MOUSE_BUTTON_3 = 2,
    KE_MOUSE_BUTTON_4 = 3,
    KE_MOUSE_BUTTON_5 = 4,
    KE_MOUSE_BUTTON_6 = 5,
    KE_MOUSE_BUTTON_7 = 6,
    KE_MOUSE_BUTTON_8 = 7,
    KE_MOUSE_BUTTON_LEFT = KE_MOUSE_BUTTON_1,
    KE_MOUSE_BUTTON_RIGHT = KE_MOUSE_BUTTON_2,
    KE_MOUSE_BUTTON_MIDDLE = KE_MOUSE_BUTTON_3,
}
