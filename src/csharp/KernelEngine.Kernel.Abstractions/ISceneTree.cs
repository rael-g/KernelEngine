namespace KernelEngine.Kernel;

/// <summary>
/// Language-agnostic scene tree contract (Tier S — S7, minimal).
/// <para>
/// Mirrors <c>ke_scene_tree</c> in the C kernel ABI. Framework's <c>Tree</c> class implements
/// this interface; non-.NET bindings (Lua, C++) interact with the same tree through this contract.
/// </para>
/// </summary>
public interface ISceneTree
{
    /// <summary>Root entity ID. Always valid for the lifetime of the tree.</summary>
    ulong Root { get; }

    /// <summary>
    /// Destroys a node and all its descendants. Fires on_destroy callbacks in post-order
    /// (children before parents). Returns <c>false</c> if the entity is not found.
    /// </summary>
    bool DestroyNode(ulong entity);

    /// <summary>Destroys all nodes. Called on application shutdown.</summary>
    void DestroyAll();

    /// <summary>
    /// Resolves a node by name or path. Returns <c>0</c> (KE_ENTITY_INVALID) if not found.
    /// </summary>
    ulong FindNode(string nameOrPath);
}
