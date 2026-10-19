using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Runtime;

namespace KernelEngine.Framework;

/// <summary>
/// Managed handle to a native world: the ECS, the runtime and the scene tree a scene is built
/// on, and the per-component registry of how a scene block fills a component. Disposing it
/// destroys the world and then the scene tree it was created with. This part declares the
/// typed <c>RegisterComponentApply</c> and the managed <c>SceneTree</c> property; the members
/// that mirror the vtable are generated.
/// </summary>
public unsafe partial class World : IDisposable
{
    private ke_scene_tree* _ownedTree;
    private readonly delegate* unmanaged[Cdecl]<ke_scene_tree*, void> _destroyTree;
    private SceneTree? _sceneTree;

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

    /// <summary>
    /// Managed wrapper over the scene tree of this world, created on first access.
    /// </summary>
    public SceneTree SceneTree => _sceneTree ??= SceneTree.Borrow(((INativeWorld)this).Native->scene_tree(((INativeWorld)this).Native));

    /// <summary>
    /// Registers an apply callback that receives the component as <typeparamref name="T"/> and
    /// the authored block as a <see cref="VariantReader"/>.
    /// </summary>
    /// <typeparam name="T">The unmanaged component struct the callback populates.</typeparam>
    /// <param name="cid">Component id returned by <c>IEcsRegistry.RegisterComponent</c>.</param>
    /// <param name="callback">
    /// Managed callback, valid only during the load. Throwing from it rejects the value and fails
    /// the load with the exception's own message.
    /// </param>
    public void RegisterComponentApply<T>(uint cid, ComponentApplyCallback<T> callback) where T : unmanaged
    {
        ArgumentNullException.ThrowIfNull(callback);
        RegisterComponentApply(cid, (component, entries, count) =>
        {
            var reader = new VariantReader(entries, count);
            callback(ref *(T*)component, in reader);
        });
    }

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
