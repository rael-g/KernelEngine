namespace KernelEngine.Framework;

/// <summary>
/// Backend contract for the scene tree (kernel-side hierarchy + path lookup + destroy).
/// Sugar layer (<c>Tree</c>) consumes this; the unsafe native wrapper lives in
/// <c>KernelEngine.Framework.Native</c>.
/// </summary>
public interface ISceneTreeBackend : IDisposable
{
    /// <summary>ECS entity that the backend keeps as the root of the hierarchy.</summary>
    ulong Root { get; }

    /// <summary>
    /// Creates a node attached under <paramref name="parent"/> (0 = the root). Initialises
    /// Transform (origin, identity, unit scale), Hierarchy (linked into the parent's child
    /// list), and Name. Returns the new entity, or 0 on failure.
    /// </summary>
    ulong CreateNode(string name, ulong parent);

    /// <summary>
    /// Resolves a name or path to an entity. Supports plain names (recursive pre-order
    /// search) and "/Absolute/Path" form. Returns <see cref="KE_ENTITY_INVALID"/> when
    /// not found.
    /// </summary>
    ulong FindNode(string nameOrPath);

    /// <summary>Destroys <paramref name="entity"/> and all its descendants.</summary>
    void DestroyNode(ulong entity);

    /// <summary>Fires the destroy hook on every node without freeing entities (shutdown).</summary>
    void DestroyAll();
}
