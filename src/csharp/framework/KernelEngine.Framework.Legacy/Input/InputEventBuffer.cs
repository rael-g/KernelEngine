using KernelEngine.Input;


namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Cross-thread queue of <see cref="InputEvent"/>s: ke.main enqueues per-frame batches drained
/// from <see cref="IInput.DrainEvents"/>; ke.sim drains them once per sim frame for dispatch
/// through the node tree. If ke.sim falls behind, multiple ke.main frames accumulate (FIFO,
/// no drops).
/// </summary>
public sealed class InputEventBuffer
{
    private readonly object _lock = new();
    private List<InputEvent> _pending = new(64);

    /// <summary>Producer side (ke.main). Copies <paramref name="events"/> into the pending list.</summary>
    public void Enqueue(ReadOnlySpan<InputEvent> events)
    {
        if (events.IsEmpty) return;
        lock (_lock)
        {
            for (int i = 0; i < events.Length; i++) _pending.Add(events[i]);
        }
    }

    /// <summary>
    /// Consumer side (ke.sim). Returns all events accumulated since the last drain and clears the
    /// internal buffer. Returns an empty array when nothing is pending — no allocation.
    /// </summary>
    public InputEvent[] Drain()
    {
        lock (_lock)
        {
            if (_pending.Count == 0) return Array.Empty<InputEvent>();
            var arr = _pending.ToArray();
            _pending.Clear();
            return arr;
        }
    }
}
