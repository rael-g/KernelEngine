using System.Collections.Concurrent;

namespace KernelEngine.Framework;

/// <summary>
/// Interns payload types as signal ids: the type's name and size are the identity of the
/// signal, and the id maps back to the type a delivery is handed to a node as.
/// </summary>
public unsafe partial class SignalBus
{
    private readonly ConcurrentDictionary<Type, uint> _signalIds = new();
    private readonly ConcurrentDictionary<uint, Type> _signalTypes = new();

    /// <summary>The id of the signal of payload type <typeparamref name="T"/>, registered on first use.</summary>
    public uint SignalIdOf<T>() where T : unmanaged =>
        _signalIds.GetOrAdd(typeof(T), type =>
        {
            var id = SignalId(type.Name, (uint)sizeof(T));
            _signalTypes[id] = type;
            return id;
        });

    /// <summary>The payload type of a signal id, or null when this bus interned none under it.</summary>
    public Type? SignalIdTypeOf(uint id) => _signalTypes.GetValueOrDefault(id);
}
