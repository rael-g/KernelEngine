namespace KernelEngine.Ecs;

/// <summary>
/// Managed view over the ECS component registry. All accessors are safe (no <c>unsafe</c>
/// at the caller); the concrete <c>EcsRegistry</c> wraps native pointer storage into spans.
/// </summary>
public interface IEcsRegistry
{
    /// <summary>Creates a new entity and returns its ID.</summary>
    ulong CreateEntity();

    /// <summary>Destroys an entity and all its components.</summary>
    void DestroyEntity(ulong entity);

    /// <summary>Registers a component type and returns its stable component ID.</summary>
    uint RegisterComponent<T>(string name) where T : unmanaged;

    /// <summary>
    /// Resolves a previously-registered component by name. Returns <c>true</c> and writes the
    /// cid into <paramref name="componentId"/> on success; returns <c>false</c> when no
    /// component with that name is known. Bindings use this to discover engine-defined
    /// components at runtime (e.g. the <c>scene_properties</c> bag the SceneLoader writes).
    /// </summary>
    bool TryLookupComponent(string name, out uint componentId);

    /// <summary>Adds (or returns existing) a component to <paramref name="entity"/>; the returned span has length 1.</summary>
    Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged;

    /// <summary>Returns a span of length 1 over the component data, or empty when absent.</summary>
    Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged;

    /// <summary>Removes a component from an entity. No-op if absent.</summary>
    void RemoveComponent(ulong entity, uint componentId);

    /// <summary>Returns true if <paramref name="entity"/> has the component with the given <paramref name="componentId"/>.</summary>
    bool HasComponent(ulong entity, uint componentId);

    /// <summary>Zero-copy query of all entities that have <paramref name="componentId"/>.</summary>
    EcsQuery<T> Query<T>(uint componentId) where T : unmanaged;
}
