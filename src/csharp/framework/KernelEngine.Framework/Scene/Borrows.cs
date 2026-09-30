namespace KernelEngine.Framework;

/// <summary>
/// Names the node a borrow parameter resolves to when the parameter's own name is
/// not the node's name. Without it a borrow binds to the child, descendant, or
/// ancestor whose name matches the parameter.
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
/// The right to raise signal <typeparamref name="T"/> from the node that declares
/// it, obtained as a parameter like any other borrow. The node names the signal it
/// raises and nothing else: who listens is a fact of the scene, wired through the
/// signal bus, so a listener can be added or removed without the emitter changing.
/// </summary>
/// <remarks>
/// <typeparamref name="T"/>'s name and size are the signal's identity across
/// languages, which is why the payload must be <c>unmanaged</c> — a managed
/// payload would be a shape only this runtime could read.
/// </remarks>
public readonly ref struct Emit<T> where T : unmanaged
{
    private readonly SignalBus? _bus;
    private readonly ulong      _source;
    private readonly uint       _signalId;

    internal Emit(SignalBus? bus, ulong source, uint signalId)
    {
        _bus      = bus;
        _source   = source;
        _signalId = signalId;
    }

    /// <summary>True when a signal bus is present to raise through.</summary>
    public bool IsBound => _bus is not null;

    /// <summary>
    /// Raises the signal with this payload. Delivery happens at the next phase
    /// boundary, not inside this call, so an emitter never runs a listener's code
    /// on its own stack.
    /// </summary>
    public unsafe void Send(in T payload)
    {
        if (_bus is null) return;
        fixed (T* p = &payload) _bus.Emit(_source, _signalId, p, (uint)sizeof(T));
    }
}
