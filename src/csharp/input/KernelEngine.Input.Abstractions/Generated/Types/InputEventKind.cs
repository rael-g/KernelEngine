using System.Numerics;

namespace KernelEngine.Input;

public enum InputEventKind : uint
{
    None = 0,
    KeyDown = 1,
    KeyUp = 2,
    MouseButtonDown = 3,
    MouseButtonUp = 4,
    MouseMove = 5,
    MouseScroll = 6,
}
