namespace KernelEngine.Input;

/// <summary>
/// The input state of one window: held keys and buttons, per-frame edges and deltas, and a queue
/// of discrete events. Frame snapshots are read through <see cref="IInputReader"/>.
/// </summary>
public interface IInput : IDisposable
{
    /// <summary>Closes the frame: clears the pressed and released edges, the mouse and scroll
    /// deltas and the event queue. Held keys, held buttons and the cursor position carry
    /// over.</summary>
    void Update();

    /// <summary>Captures a copy of the current state as an <see cref="IInputReader"/>; the copy
    /// does not change as the live state moves on.</summary>
    IInputReader CaptureSnapshot();

    /// <summary>
    /// Moves the queued events into <paramref name="buffer"/> and empties the queue; events beyond
    /// the buffer's length are discarded. Returns the number of events written.
    /// </summary>
    int DrainEvents(Span<InputEvent> buffer);
}
