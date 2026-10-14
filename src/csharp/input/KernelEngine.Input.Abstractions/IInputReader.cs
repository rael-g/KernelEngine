using System.Numerics;

namespace KernelEngine.Input;

/// <summary>
/// Read-only per-frame input state: held keys and buttons, the edges that occurred since the
/// previous <see cref="IInput.Update"/>, the cursor position and the per-frame deltas.
/// </summary>
public interface IInputReader
{
    /// <summary>True while the key is held.</summary>
    bool IsKeyDown(Key key);

    /// <summary>True for exactly the tick the key transitioned from up to down (rising
    /// edge).</summary>
    bool IsKeyPressed(Key key);

    /// <summary>True for exactly the tick the key transitioned from down to up (falling
    /// edge).</summary>
    bool IsKeyReleased(Key key);

    /// <summary>The cursor position.</summary>
    Vector2 MousePosition { get; }
    /// <summary>The cursor movement accumulated this frame.</summary>
    Vector2 MouseDelta { get; }
    /// <summary>The scroll amount accumulated this frame.</summary>
    Vector2 ScrollDelta { get; }

    /// <summary>True while the mouse button is held.</summary>
    bool IsMouseButtonDown(MouseButton button);
}
