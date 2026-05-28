using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A physical-input source that contributes a value to an <see cref="InputAction"/> each frame.
/// Multiple bindings on the same action are allowed (keyboard + gamepad + composite all coexist —
/// the action's combined value is the max-magnitude / OR of all bindings, per the spec §5).
/// </summary>
public abstract class InputBinding
{
    /// <summary>The value-shape this binding emits. Must match its action's <see cref="ActionType"/>.</summary>
    public abstract ActionType Type { get; }

    /// <summary>
    /// Reads the binding's current value for this frame.
    /// <paramref name="x"/>/<paramref name="y"/>/<paramref name="z"/> hold the result.
    /// For <see cref="ActionType.Button"/>, <paramref name="x"/> is 0 or 1 (currently held).
    /// </summary>
    public abstract void Sample(IInputReader reader, out float x, out float y, out float z);
}

/// <summary>Button binding driven by a single keyboard key. Emits 1 while held, 0 otherwise.</summary>
public sealed class KeyBinding(Key key) : InputBinding
{
    public Key Key { get; } = key;

    public override ActionType Type => ActionType.Button;

    public override void Sample(IInputReader reader, out float x, out float y, out float z)
    {
        x = reader.IsKeyDown((int)Key) ? 1f : 0f;
        y = 0f;
        z = 0f;
    }
}

/// <summary>Button binding driven by a single mouse button. Emits 1 while held, 0 otherwise.</summary>
public sealed class MouseButtonBinding(MouseButton button) : InputBinding
{
    public MouseButton Button { get; } = button;

    public override ActionType Type => ActionType.Button;

    public override void Sample(IInputReader reader, out float x, out float y, out float z)
    {
        x = reader.IsMouseButtonDown((int)Button) ? 1f : 0f;
        y = 0f;
        z = 0f;
    }
}

/// <summary>
/// Axis1D binding composed of two keys: <paramref name="negative"/> emits -1, <paramref name="positive"/>
/// emits +1; both held cancels to 0. The classic "A/D = strafe" pattern as a first-class binding.
/// </summary>
public sealed class KeyPairAxis1DBinding(Key negative, Key positive) : InputBinding
{
    public Key Negative { get; } = negative;
    public Key Positive { get; } = positive;

    public override ActionType Type => ActionType.Axis1D;

    public override void Sample(IInputReader reader, out float x, out float y, out float z)
    {
        float v = 0f;
        if (reader.IsKeyDown((int)Negative)) v -= 1f;
        if (reader.IsKeyDown((int)Positive)) v += 1f;
        x = v;
        y = 0f;
        z = 0f;
    }
}

/// <summary>
/// Axis2D binding composed of four keys (up/down/left/right). Used to build WASD/Arrows movement
/// as a single Vector2 action — see <see cref="Vector2Composite"/> for the factories.
/// </summary>
public sealed class KeyQuadAxis2DBinding(Key up, Key down, Key left, Key right) : InputBinding
{
    public Key Up    { get; } = up;
    public Key Down  { get; } = down;
    public Key Left  { get; } = left;
    public Key Right { get; } = right;

    public override ActionType Type => ActionType.Axis2D;

    public override void Sample(IInputReader reader, out float x, out float y, out float z)
    {
        float vx = 0f, vy = 0f;
        if (reader.IsKeyDown((int)Left))  vx -= 1f;
        if (reader.IsKeyDown((int)Right)) vx += 1f;
        if (reader.IsKeyDown((int)Down))  vy -= 1f;
        if (reader.IsKeyDown((int)Up))    vy += 1f;
        x = vx;
        y = vy;
        z = 0f;
    }
}
