using System.Runtime.InteropServices;
using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Runtime;

namespace KernelEngine.Framework;

/// <summary>
/// The parts of <see cref="World"/> that are not a direct image of the C ABI: the typed
/// overload of <c>RegisterComponentApply</c>, which reinterprets the component's memory
/// as the struct the caller declared, and the <c>Ecs</c>/<c>Runtime</c>/<c>SceneTree</c>
/// properties, which expose the already-owned managed wrappers this world was constructed
/// with rather than re-deriving them from the native accessors. Everything that mirrors
/// the vtable 1:1 is generated in <c>Generated/World.g.cs</c>.
/// </summary>
public unsafe partial class World : IDisposable
{
    private ke_scene_tree* _ownedTree;
    private readonly delegate* unmanaged[Cdecl]<ke_scene_tree*, void> _destroyTree;
    private SceneTree? _sceneTree;

    /// <summary>ECS registry borrowed by this world. Same instance as the DI-registered <see cref="IEcsRegistry"/>.</summary>
    public IEcsRegistry Ecs { get; }

    /// <summary>Runtime borrowed by this world. Same instance as the DI-registered <see cref="IRuntime"/>.</summary>
    public IRuntime Runtime { get; }

    /// <summary>
    /// Creates a <see cref="World"/> wrapper that also owns <paramref name="ownedTree"/>,
    /// destroying it on <see cref="Dispose"/> after the world is destroyed.
    /// </summary>
    public World(ke_world_handle worldHandle, ke_scene_tree_handle treeHandle, IEcsRegistry ecs, IRuntime runtime)
        : this(worldHandle)
    {
        _ownedTree   = treeHandle.@ref;
        _destroyTree = treeHandle.destroy;
        Ecs          = ecs;
        Runtime      = runtime;
    }

    /// <summary>
    /// Managed wrapper over the scene tree embedded in this world. Created on
    /// first access and cached for the lifetime of the world.
    /// </summary>
    public SceneTree SceneTree => _sceneTree ??= SceneTree.Borrow(((INativeWorld)this).Native->scene_tree(((INativeWorld)this).Native));

    /// <summary>
    /// Registers an apply callback that reads the component as
    /// <typeparamref name="T"/>. The scene loader hands the component's memory over
    /// untyped, since the ABI has no way to name a struct the caller declared.
    /// </summary>
    /// <typeparam name="T">The unmanaged component struct the callback populates.</typeparam>
    /// <param name="cid">Component id returned by <c>IEcsRegistry.RegisterComponent</c>.</param>
    /// <param name="callback">
    /// Managed callback; must not be stored across frames. Throwing from it rejects
    /// the value and fails the load with the exception's own message, which is how a
    /// callback reports a key it owns carrying something it cannot map.
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
