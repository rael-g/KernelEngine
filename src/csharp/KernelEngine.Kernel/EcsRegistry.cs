using System.Text;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper for <c>ke_ecs</c> (Tier S S5 — ECS vtable contract).
/// All calls route through the language-agnostic vtable so the sparse-set implementation
/// can be replaced by an archetype plugin without touching this class.
/// </summary>
public sealed unsafe class EcsRegistry : IEcsRegistry
{
    private readonly ke_ecs* _native;

    internal EcsRegistry(ke_ecs* native) => _native = native;

    // ── Entity lifetime ───────────────────────────────────────────────────────

    /// <inheritdoc/>
    public ulong CreateEntity() => _native->entity_create(_native);

    /// <inheritdoc/>
    public void DestroyEntity(ulong entity) => _native->entity_destroy(_native, entity);

    // ── Component schema ──────────────────────────────────────────────────────

    /// <inheritdoc/>
    public uint RegisterComponent<T>(string name) where T : unmanaged
    {
        var bytes = Encoding.UTF8.GetBytes(name + '\0');
        fixed (byte* namePtr = bytes)
            return _native->component_register(_native, (sbyte*)namePtr, (nuint)sizeof(T));
    }

    /// <inheritdoc/>
    public bool TryLookupComponent(string name, out uint componentId)
    {
        var bytes = Encoding.UTF8.GetBytes(name + '\0');
        ke_component_meta meta;
        fixed (byte* namePtr = bytes)
        {
            var rc = _native->component_lookup(_native, (sbyte*)namePtr, &meta);
            if (rc == ke_result.KE_OK)
            {
                componentId = meta.cid;
                return true;
            }
        }
        componentId = 0;
        return false;
    }

    // ── Component data ────────────────────────────────────────────────────────

    /// <inheritdoc cref="IEcsRegistry.AddComponent{T}"/>
    public Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged
    {
        var ptr = (T*)_native->component_add(_native, entity, componentId);
        return new Span<T>(ptr, 1);
    }

    /// <summary>Pointer-returning overload (engine-internal hot path).</summary>
    internal T* AddComponentRaw<T>(ulong entity, uint componentId) where T : unmanaged =>
        (T*)_native->component_add(_native, entity, componentId);

    /// <inheritdoc cref="IEcsRegistry.GetComponent{T}"/>
    public Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged
    {
        var ptr = (T*)_native->component_get(_native, entity, componentId);
        return ptr == null ? Span<T>.Empty : new Span<T>(ptr, 1);
    }

    /// <summary>Pointer-returning overload (engine-internal hot path).</summary>
    internal T* GetComponentRaw<T>(ulong entity, uint componentId) where T : unmanaged =>
        (T*)_native->component_get(_native, entity, componentId);

    /// <inheritdoc/>
    public void RemoveComponent(ulong entity, uint componentId) =>
        _native->component_remove(_native, entity, componentId);

    /// <inheritdoc/>
    public bool HasComponent(ulong entity, uint componentId) =>
        _native->component_get(_native, entity, componentId) != null;

    // ── Query ─────────────────────────────────────────────────────────────────

    /// <inheritdoc/>
    public EcsQuery<T> Query<T>(uint componentId) where T : unmanaged
    {
        ulong* entities;
        void* data;
        nuint count;
        _native->query(_native, componentId, &entities, &data, &count);
        return new EcsQuery<T>(
            new ReadOnlySpan<ulong>(entities, (int)count),
            new Span<T>((T*)data, (int)count));
    }
}
