namespace KernelEngine.Kernel;

/// <summary>
/// The input service that processes OS messages on <c>ke.main</c> and produces frame snapshots
/// consumable by <c>ke.sim</c> via <see cref="IInputReader"/>.
/// </summary>
public interface IInput : IDisposable
{
    /// <summary>Processes pending messages and updates internal state. Must run on ke.main.</summary>
    Result Update();

    /// <summary>Captures an immutable input snapshot for the current frame, marshalled to a
    /// managed <see cref="IInputReader"/>. Safe to publish across threads (e.g. via
    /// <see cref="IInputBuffer"/>).</summary>
    IInputReader CaptureSnapshot();

    /// <summary>
    /// Drains all events captured since the last call into <paramref name="buffer"/>.
    /// Returns the number of events written (<= <c>buffer.Length</c>). Must run on ke.main.
    /// </summary>
    int DrainEvents(Span<InputEvent> buffer);
}
