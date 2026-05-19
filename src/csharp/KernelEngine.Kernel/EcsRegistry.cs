using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper for <c>ke_ecs_registry</c>. Provides typed component registration,
/// add/get/remove, and cache-friendly iteration via <see cref="Query{T}"/>.
/// </summary>
public sealed unsafe class EcsRegistry : IEcsRegistry
{
    /// <inheritdoc/>
    public bool HasComponent(ulong entity, uint cid) =>
        NativeMethods.ecs_component_get(_native, entity, cid) != null;

    private readonly ke_ecs_registry* _native;

    public ke_ecs_registry* Native => _native;

    internal EcsRegistry(ke_ecs_registry* native) => _native = native;

    /// <summary>Creates a new entity and returns its ID.</summary>
    public ulong CreateEntity() => NativeMethods.ecs_entity_create(_native);

    /// <summary>Destroys an entity and removes all its components.</summary>
    public void DestroyEntity(ulong entity) => NativeMethods.ecs_entity_destroy(_native, entity);

    /// <summary>Registers a component type and returns its stable ID.</summary>
    public uint RegisterComponent<T>(string name) where T : unmanaged
    {
        var bytes = Encoding.UTF8.GetBytes(name + '\0');
        fixed (byte* namePtr = bytes)
            return NativeMethods.ecs_component_register(_native, (sbyte*)namePtr, (nuint)sizeof(T));
    }

    /// <summary>Adds a component to an entity and returns a reference to it (zeroed).</summary>
    public ref T AddComponent<T>(ulong entity, uint componentId) where T : unmanaged
    {
        var ptr = (T*)NativeMethods.ecs_component_add(_native, entity, componentId);
        return ref *ptr;
    }

    /// <summary>Returns a reference to a component, or <c>null</c> if not present.</summary>
    public T* GetComponent<T>(ulong entity, uint componentId) where T : unmanaged =>
        (T*)NativeMethods.ecs_component_get(_native, entity, componentId);

    /// <summary>Removes a component from an entity.</summary>
    public void RemoveComponent(ulong entity, uint componentId) =>
        NativeMethods.ecs_component_remove(_native, entity, componentId);

    /// <summary>
    /// Returns a zero-copy view of all entities and their contiguous component data
    /// for a given component type. The result is valid until the next structural change.
    /// </summary>
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
