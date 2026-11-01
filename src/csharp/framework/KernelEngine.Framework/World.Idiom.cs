using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Runtime;

namespace KernelEngine.Framework;

/// <summary>
/// Managed handle to a native world: the ECS, the runtime and the scene tree a scene is built
/// on, and the per-component registry of how a scene block fills a component. Disposing it
/// destroys the world and then the scene tree it was created with. The members that mirror
/// the vtable are generated.
/// </summary>
public unsafe partial class World : IDisposable
{
    private ke_scene_tree* _ownedTree;
    private readonly delegate* unmanaged[Cdecl]<ke_scene_tree*, void> _destroyTree;

    /// <summary>
    /// Creates a <see cref="World"/> wrapper that also owns the scene tree of
    /// <paramref name="treeHandle"/>, destroying it on <see cref="Dispose"/> after the world is
    /// destroyed.
    /// </summary>
    public World(ke_world_handle worldHandle, ke_scene_tree_handle treeHandle)
        : this(worldHandle)
    {
        _ownedTree = treeHandle.@ref;
        _destroyTree = treeHandle.destroy;
    }

    /// <summary>Managed wrapper over the scene tree of this world, borrowed.</summary>
    public SceneTree Tree => KernelEngine.Framework.SceneTree.Borrow(((INativeWorld)this).Native->scene_tree(((INativeWorld)this).Native));

    /// <summary>Also releases the owned scene tree.</summary>
    partial void OnDispose()
    {
        if (_ownedTree is not null)
        {
            if (_destroyTree != null) _destroyTree(_ownedTree);
            _ownedTree = null;
        }
    }
}
