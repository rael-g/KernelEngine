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

    /// <summary>
    /// Registers a component type with the field table <typeparamref name="T"/> states, and returns
    /// its stable component ID. A name registered before with a table that disagrees in a field's
    /// name, kind, offset or size is refused.
    /// </summary>
    /// <exception cref="InvalidOperationException">The native registry refused the registration.</exception>
    uint RegisterComponent<T>(string name) where T : unmanaged, IComponentLayout;

    /// <summary>
    /// Resolves a previously-registered component by name. Returns <c>true</c> and writes the
    /// cid into <paramref name="componentId"/> on success; returns <c>false</c> when no
    /// component with that name is known. Bindings use this to discover engine-defined
    /// components at runtime (e.g. a game-defined component a scene file authors).
    /// </summary>
    bool TryLookupComponent(string name, out uint componentId);

    /// <summary>Adds (or returns existing) a component to <paramref name="entity"/>; the returned span has length 1 and is valid until the next structural change on this registry.</summary>
    Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged;

    /// <summary>Returns a span of length 1 over the component data, or empty when absent; valid until the next structural change on this registry.</summary>
    Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged;

    /// <summary>Removes a component from an entity. No-op if absent.</summary>
    void RemoveComponent(ulong entity, uint componentId);

    /// <summary>Returns true if <paramref name="entity"/> has the component with the given <paramref name="componentId"/>.</summary>
    bool HasComponent(ulong entity, uint componentId);
}
