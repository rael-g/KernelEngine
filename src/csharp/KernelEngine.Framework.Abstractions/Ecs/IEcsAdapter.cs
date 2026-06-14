namespace KernelEngine.Framework;

/// <summary>
/// Thin managed bridge over a raw ECS implementation. Consumed by <c>Tree</c>
/// (Toolkit) and registered by <c>FrameworkModule</c> (Framework) so Toolkit
/// never takes a direct dependency on the concrete <c>EcsAdapter</c>.
/// </summary>
public interface IEcsAdapter
{
    /// <summary>Registers an unmanaged component type and returns its runtime ID.</summary>
    uint Register<T>(string name) where T : unmanaged;

    /// <summary>Creates a new entity and returns its ID.</summary>
    ulong CreateEntity();

    /// <summary>Destroys the entity and all components attached to it.</summary>
    void EntityDestroy(ulong entity);

    /// <summary>Adds or overwrites component <typeparamref name="T"/> on an entity.</summary>
    void Add<T>(ulong entity, uint cid, in T value) where T : unmanaged;

    /// <summary>
    /// Tries to read component <typeparamref name="T"/> from an entity.
    /// Returns false if the entity does not have the component.
    /// </summary>
    bool TryGet<T>(ulong entity, uint cid, out T value) where T : unmanaged;

    /// <summary>Invokes <paramref name="action"/> for every entity that has component <typeparamref name="T"/>.</summary>
    void Query<T>(uint cid, QueryAction<T> action) where T : unmanaged;
}

/// <summary>Callback signature for <see cref="IEcsAdapter.Query{T}"/>.</summary>
public delegate void QueryAction<T>(ulong entity, ref T component) where T : unmanaged;
