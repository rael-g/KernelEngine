using System.Numerics;

namespace KernelEngine.Input;

public partial struct InputEvent
{
    public InputEventKind Kind;
    public Key Key;
    public MouseButton Button;
    public System.Numerics.Vector2 Scroll;
    public System.Numerics.Vector2 Position;

    public bool Handled;
}
