namespace KernelEngine.Framework;

/// <summary>
/// Names the node a borrow parameter resolves to. Without it the borrow matches on type alone.
/// </summary>
[AttributeUsage(AttributeTargets.Parameter)]
public sealed class NodeNameAttribute : Attribute
{
    /// <summary>The scene name of the node this parameter borrows.</summary>
    public string Name { get; }

    /// <param name="name">The scene name of the node this parameter borrows.</param>
    public NodeNameAttribute(string name) => Name = name;
}

/// <summary>
/// The right to raise signal <typeparamref name="T"/> from the node that declares it, obtained
/// as a parameter of <c>Update</c> like any other borrow.
/// </summary>
public readonly ref struct Emit<T> where T : unmanaged
{
    private readonly SignalBus? _bus;
    private readonly ulong _source;
    private readonly uint _signalId;

    internal Emit(SignalBus? bus, ulong source, uint signalId)
    {
        _bus = bus;
        _source = source;
        _signalId = signalId;
    }

    /// <summary>True when a signal bus is present to raise through.</summary>
    public bool IsBound => _bus is not null;

    /// <summary>
    /// Raises the signal with this payload. Delivery happens at the next phase boundary, not
    /// inside this call. Does nothing when no signal bus is present.
    /// </summary>
    public unsafe void Send(in T payload)
    {
        if (_bus is null) return;
        fixed (T* p = &payload) _bus.Emit(_source, _signalId, p, (uint)sizeof(T));
    }
}
