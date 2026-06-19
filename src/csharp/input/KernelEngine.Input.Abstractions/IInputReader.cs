using System.Numerics;

namespace KernelEngine.Kernel;

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
    bool IsKeyDown(int keyCode);

    Vector2 MousePosition { get; }
    Vector2 MouseDelta { get; }
    Vector2 ScrollDelta { get; }

    bool IsMouseButtonDown(int button);
}
