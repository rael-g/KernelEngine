using System.Text;

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
    public uint RegisterComponent<T>(string name) where T : unmanaged, IComponentLayout
    {
        var utf8 = Encoding.UTF8.GetBytes(name + '\0');
        fixed (byte* n = utf8)
        {
            var p = new ke_component_params
            {
                name = (sbyte*)n,
                size = (nuint)sizeof(T),
                alignment = (nuint)(sizeof(AlignmentProbe<T>) - sizeof(T)),
                fields = NativeFieldTable<T>.Fields,
                field_count = (uint)NativeFieldTable<T>.Length,
            };
            return ComponentRegister(&p);
        }
    }

    private readonly struct AlignmentProbe<T>(byte head, T value) where T : unmanaged
    {
        public readonly byte Head = head;
        public readonly T Value = value;
    }

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
