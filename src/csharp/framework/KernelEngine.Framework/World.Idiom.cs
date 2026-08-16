using System.Runtime.InteropServices;
using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Runtime;

namespace KernelEngine.Framework;

/// <summary>
/// The parts of <see cref="World"/> that are not a direct image of the C ABI: the
/// scene-tree/apply-registration surface (<c>register_component_apply</c> takes a bare
/// C function pointer with no ABI-derivable managed shape — a GC-pinned bridge per
/// registered component type is entirely hand-written), and the <c>Ecs</c>/<c>Runtime</c>/
/// <c>SceneTree</c> properties, which expose the already-owned managed wrappers this
/// world was constructed with rather than re-deriving them from the native accessors.
/// Everything that mirrors the vtable 1:1 is generated in <c>Generated/World.g.cs</c>.
/// </summary>
public unsafe partial class World : IDisposable
{
    private ke_scene_tree* _ownedTree;
    private readonly delegate* unmanaged[Cdecl]<ke_scene_tree*, void> _destroyTree;
    private SceneTree? _sceneTree;

    private readonly List<GCHandle> _applyHandles = [];

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
    /// Registers a managed apply callback for the given component id. The callback
    /// is invoked by the native scene loader whenever an
    /// <c>[entity.components.X]</c> block maps to <paramref name="cid"/>.
    /// </summary>
    /// <typeparam name="T">The unmanaged component struct the callback populates.</typeparam>
    /// <param name="cid">Component id returned by <c>IEcsRegistry.RegisterComponent</c>.</param>
    /// <param name="callback">
    /// Managed callback; must not be stored across frames. Throwing from it rejects
    /// the value and fails the load, which is how a callback reports a key it owns
    /// carrying something it cannot map.
    /// </param>
    public void RegisterComponentApply<T>(uint cid, ComponentApplyCallback<T> callback) where T : unmanaged
    {
        var bridge = new ApplyBridge<T>(callback);
        var del    = new ApplyNativeFn(bridge.Invoke);
        _applyHandles.Add(GCHandle.Alloc(del));

        var fnPtr = (delegate* unmanaged[Cdecl]<void*, ke_variant_table_entry*, uint, bool>)
            Marshal.GetFunctionPointerForDelegate(del).ToPointer();

        var native = ((INativeWorld)this).Native;
        ke_error* err = null;
        KernelError.ThrowIfFailed(
            native->register_component_apply(native, cid, fnPtr, &err), err, "register_component_apply");
    }

    /// <summary>Also releases the owned scene tree and the GC handles kept for registered apply callbacks.</summary>
    partial void OnDispose()
    {
        if (_ownedTree is not null)
        {
            if (_destroyTree != null) _destroyTree(_ownedTree);
            _ownedTree = null;
        }
        foreach (var h in _applyHandles)
            if (h.IsAllocated) h.Free();
        _applyHandles.Clear();
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private unsafe delegate bool ApplyNativeFn(void* comp, ke_variant_table_entry* entries, uint count);

    /// <summary>
    /// Per-type bridge that holds the managed callback and exposes an instance
    /// method matching <see cref="ApplyNativeFn"/> so
    /// <see cref="Marshal.GetFunctionPointerForDelegate"/> can produce a stable
    /// native thunk without requiring <c>[UnmanagedCallersOnly]</c> on generic code.
    /// </summary>
    private sealed class ApplyBridge<T> where T : unmanaged
    {
        private readonly ComponentApplyCallback<T> _callback;

        internal ApplyBridge(ComponentApplyCallback<T> callback) => _callback = callback;

        internal unsafe bool Invoke(void* comp, ke_variant_table_entry* entries, uint count)
        {
            try
            {
                var reader    = new VariantReader(entries, count);
                ref var typed = ref *(T*)comp;
                _callback(ref typed, in reader);
                return true;
            }
            catch (Exception ex)
            {
                SceneLoader.ParkException(ex);
                return false;
            }
        }
    }
}
