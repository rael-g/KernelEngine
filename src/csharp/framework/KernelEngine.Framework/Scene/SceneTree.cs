using System.Text;
using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper over the native <c>ke_scene_tree</c> vtable.
/// Creates and destroys entities with the required Transform + Hierarchy + Name
/// components automatically; provides path-based node lookup.
/// </summary>
public sealed unsafe class SceneTree : INativeSceneTree
{
    private ke_scene_tree* _native;

    ke_scene_tree* INativeSceneTree.Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    internal SceneTree(ke_scene_tree* native) => _native = native;

    /// <summary>Root entity. Always valid for the lifetime of the tree.</summary>
    public ulong Root => _native->root(_native);

    /// <summary>
    /// Creates a new node attached under <paramref name="parent"/>
    /// (<c>0</c> = root). Returns the new entity ID, or <c>0</c> on failure.
    /// </summary>
    public ulong CreateNode(string name, ulong parent = 0)
    {
        var bytes = Encoding.UTF8.GetBytes(name + "\0");
        fixed (byte* p = bytes)
            return _native->create_node(_native, (sbyte*)p, parent);
    }

    /// <summary>
    /// Destroys a node and all its descendants. Fires on_destroy hooks in
    /// post-order (children before parents).
    /// </summary>
    public Result DestroyNode(ulong entity)
        => _native->destroy_node(_native, entity, null).ToManaged();

    /// <summary>Destroys all nodes. Used on scene shutdown.</summary>
    public void DestroyAll() => _native->destroy_all(_native);

    /// <summary>
    /// Resolves a node by name (<c>"Name"</c>) or absolute path
    /// (<c>"/Root/Child"</c>). Returns <c>0</c> when not found.
    /// </summary>
    public ulong FindNode(string nameOrPath)
    {
        var bytes = Encoding.UTF8.GetBytes(nameOrPath + "\0");
        fixed (byte* p = bytes)
            return _native->find_node(_native, (sbyte*)p);
    }

    /// <summary>
    /// Propagates local transforms down the hierarchy, writing each entity's
    /// <c>world_matrix</c> as <c>parent_world * TRS_local</c>.
    /// Call once per frame before any system that reads <c>WorldMatrix</c>.
    /// </summary>
    public void PropagateTransforms() => _native->propagate_transforms(_native);
}
