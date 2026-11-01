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
    public Entity CreateEntity() => EntityCreate();

    /// <inheritdoc/>
    public void DestroyEntity(Entity entity) => EntityDestroy(entity);

    /// <inheritdoc/>
    public ComponentId RegisterComponent<T>(string name) where T : unmanaged =>
        ComponentRegister(name, (nuint)sizeof(T), (nuint)(sizeof(AlignmentProbe<T>) - sizeof(T)), default);

    /// <summary>
    /// Registers <typeparamref name="T"/> with the field table its type states, so a scene can
    /// address its fields. The table stays allocated for the life of the process.
    /// </summary>
    public ComponentId RegisterLaidOutComponent<T>(string name) where T : unmanaged, IComponentLayout
    {
        var fields = T.Fields;
        var native = new global::KernelEngine.Ecs.Native.ComponentField[fields.Length];
        for (var i = 0; i < fields.Length; i++)
        {
            native[i] = default;
            native[i].Name = (sbyte*)System.Runtime.InteropServices.Marshal.StringToCoTaskMemUTF8(fields[i].Name);
            native[i].Type = (VariantType)(uint)fields[i].Kind;
            native[i].Offset = fields[i].Offset;
            native[i].Size = fields[i].Size;
        }
        return ComponentRegister(name, (nuint)sizeof(T), (nuint)(sizeof(AlignmentProbe<T>) - sizeof(T)), native);
    }

    private readonly struct AlignmentProbe<T>(byte head, T value) where T : unmanaged
    {
        public readonly byte Head = head;
        public readonly T Value = value;
    }

    /// <inheritdoc/>
    public bool TryLookupComponent(string name, out ComponentId componentId)
    {
        if (TryComponentLookup(name, out var meta))
        {
            componentId = meta.Cid;
            return true;
        }
        componentId = default;
        return false;
    }

    /// <inheritdoc cref="IEcsRegistry.AddComponent{T}"/>
    public Span<T> AddComponent<T>(Entity entity, ComponentId componentId) where T : unmanaged
    {
        var ptr = (T*)ComponentAdd(entity, componentId);
        return ptr != null ? new Span<T>(ptr, 1) : Span<T>.Empty;
    }

    /// <inheritdoc cref="IEcsRegistry.GetComponent{T}"/>
    public Span<T> GetComponent<T>(Entity entity, ComponentId componentId) where T : unmanaged
    {
        var ptr = (T*)ComponentGet(entity, componentId);
        return ptr != null ? new Span<T>(ptr, 1) : Span<T>.Empty;
    }

    /// <inheritdoc/>
    public void RemoveComponent(Entity entity, ComponentId componentId) => ComponentRemove(entity, componentId);

    /// <inheritdoc/>
    public bool HasComponent(Entity entity, ComponentId componentId) => ComponentGet(entity, componentId) != 0;
}
