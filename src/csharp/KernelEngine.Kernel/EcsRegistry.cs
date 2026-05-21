using System.Text;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper for <c>ke_ecs_registry</c>. Provides typed component registration,
/// add/get/remove, and cache-friendly iteration via <see cref="Query{T}"/>.
/// </summary>
public sealed unsafe class EcsRegistry : IEcsRegistry
{
    private readonly ke_ecs_registry* _native;

    public ke_ecs_registry* Native => _native;

    internal EcsRegistry(ke_ecs_registry* native) => _native = native;

    /// <inheritdoc/>
    public ulong CreateEntity() => NativeMethods.ecs_entity_create(_native);

    /// <inheritdoc/>
    public void DestroyEntity(ulong entity) => NativeMethods.ecs_entity_destroy(_native, entity);

    /// <inheritdoc/>
    public uint RegisterComponent<T>(string name) where T : unmanaged
    {
        var bytes = Encoding.UTF8.GetBytes(name + '\0');
        fixed (byte* namePtr = bytes)
            return NativeMethods.ecs_component_register(_native, (sbyte*)namePtr, (nuint)sizeof(T));
    }

    /// <inheritdoc cref="IEcsRegistry.AddComponent{T}"/>
    public Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged
    {
        var ptr = (T*)NativeMethods.ecs_component_add(_native, entity, componentId);
        return new Span<T>(ptr, 1);
    }

    /// <summary>Pointer-returning overload (engine-internal hot path).</summary>
    internal T* AddComponentRaw<T>(ulong entity, uint componentId) where T : unmanaged =>
        (T*)NativeMethods.ecs_component_add(_native, entity, componentId);

    /// <inheritdoc cref="IEcsRegistry.GetComponent{T}"/>
    public Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged
    {
        var ptr = (T*)NativeMethods.ecs_component_get(_native, entity, componentId);
        return ptr == null ? Span<T>.Empty : new Span<T>(ptr, 1);
    }

    /// <summary>Pointer-returning overload (engine-internal hot path).</summary>
    internal T* GetComponentRaw<T>(ulong entity, uint componentId) where T : unmanaged =>
        (T*)NativeMethods.ecs_component_get(_native, entity, componentId);

    /// <inheritdoc/>
    public void RemoveComponent(ulong entity, uint componentId) =>
        NativeMethods.ecs_component_remove(_native, entity, componentId);

    /// <inheritdoc/>
    public bool HasComponent(ulong entity, uint componentId) =>
        NativeMethods.ecs_component_get(_native, entity, componentId) != null;

    /// <inheritdoc/>
    public EcsQuery<T> Query<T>(uint componentId) where T : unmanaged
    {
        ulong* entities;
        void* data;
        nuint count;
        NativeMethods.ecs_registry_query(_native, componentId, &entities, &data, &count);
        return new EcsQuery<T>(
            new ReadOnlySpan<ulong>(entities, (int)count),
            new Span<T>((T*)data, (int)count));
    }
}
