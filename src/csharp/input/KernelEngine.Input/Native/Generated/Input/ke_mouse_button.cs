using KernelEngine.Common.Native;

namespace KernelEngine.Input.Native;

[NativeTypeName("unsigned int")]
public enum ke_mouse_button : uint
{
    KE_MOUSE_BUTTON_LEFT = 0,
    KE_MOUSE_BUTTON_RIGHT = 1,
    KE_MOUSE_BUTTON_MIDDLE = 2,
}
