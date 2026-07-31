using System.Numerics;

namespace KernelEngine.Input;

/// <summary>
/// Read-only interface for per-frame input state. Used by the simulation thread.
///
/// <para>
/// Only <b>level state</b> (currently held / current cursor position) is exposed here, because that
/// is the only signal the single-slot snapshot exchange (<c>InputBuffer</c>) can deliver reliably.
/// </para>
///
/// <para>
/// For <b>edge events</b> (key just pressed / just released, button clicked, scroll wheel ticks),
/// subscribe via <c>Node.OnInput(ref InputEvent)</c> — events flow through a kernel ring buffer
/// drained per frame, so nothing is lost when ke.main produces snapshots faster than ke.sim consumes.
/// The action layer (chapter 22) will eventually offer <c>WasActionPressed(action)</c> derived from
/// the same event stream.
/// </para>
/// </summary>
public interface IInputReader
{
    bool IsKeyDown(Key key);

    /// <summary>True for exactly the tick the key transitioned from up to down (rising edge).</summary>
    bool IsKeyPressed(Key key);

    /// <summary>True for exactly the tick the key transitioned from down to up (falling edge).</summary>
    bool IsKeyReleased(Key key);

    Vector2 MousePosition { get; }
    Vector2 MouseDelta { get; }
    Vector2 ScrollDelta { get; }

    bool IsMouseButtonDown(MouseButton button);
}
