using KernelEngine.Ecs.Native;

namespace KernelEngine.Ecs;

/// <summary>
/// The part of <see cref="EcsRegistry"/> that implements <see cref="IEcsRegistry"/>: the generic,
/// span-returning component accessors over the native slots.
/// </summary>
public unsafe partial class EcsRegistry : IEcsRegistry
{
    /// <inheritdoc/>
    public ulong CreateEntity() => EntityCreate();

    /// <inheritdoc/>
    public void DestroyEntity(ulong entity) => EntityDestroy(entity);

    /// <inheritdoc/>
    public uint RegisterComponent<T>(string name) where T : unmanaged =>
        ComponentRegister(name, (nuint)sizeof(T), null, 0);

    /// <inheritdoc/>
    public bool TryLookupComponent(string name, out uint componentId)
    {
        if (TryComponentLookup(name, out var meta))
        {
            componentId = meta.cid;
            return true;
        }
        componentId = 0;
        return false;
    }

    /// <inheritdoc cref="IEcsRegistry.AddComponent{T}"/>
    public Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged
    {
        var ptr = (T*)ComponentAdd(entity, componentId);
        return ptr != null ? new Span<T>(ptr, 1) : Span<T>.Empty;
    }

    /// <inheritdoc cref="IEcsRegistry.GetComponent{T}"/>
    public Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged
    {
        var ptr = (T*)ComponentGet(entity, componentId);
        return ptr != null ? new Span<T>(ptr, 1) : Span<T>.Empty;
    }

    /// <inheritdoc/>
    public void RemoveComponent(ulong entity, uint componentId) => ComponentRemove(entity, componentId);

    /// <inheritdoc/>
    public bool HasComponent(ulong entity, uint componentId) => ComponentGet(entity, componentId) != 0;
}
