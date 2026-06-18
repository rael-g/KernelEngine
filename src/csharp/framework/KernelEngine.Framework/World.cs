using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper over the native <c>ke_world</c> vtable. Exposes scene-level
/// operations (loading, component apply registration) as managed APIs; does not
/// re-expose the underlying ECS, runtime, or scene-tree native pointers.
/// </summary>
public sealed unsafe class World : IDisposable, INativeWorld
{
    private ke_world*      _native;
    private ke_scene_tree* _ownedTree;
    private readonly delegate* unmanaged[Cdecl]<ke_world*, void>      _destroyWorld;
    private readonly delegate* unmanaged[Cdecl]<ke_scene_tree*, void> _destroyTree;
    private SceneTree?     _sceneTree;

    // Keeps managed apply delegate wrappers alive so the GC doesn't collect
    // them while native code holds the function pointer.
    private readonly List<GCHandle> _applyHandles = [];

    ke_world* INativeWorld.Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    /// <summary>ECS registry borrowed by this world. Same instance as the DI-registered <see cref="IEcsRegistry"/>.</summary>
    public IEcsRegistry Ecs { get; }

    /// <summary>Runtime borrowed by this world. Same instance as the DI-registered <see cref="IRuntime"/>.</summary>
    public IRuntime Runtime { get; }

    /// <summary>
    /// Creates a <see cref="World"/> wrapper that also owns <paramref name="ownedTree"/>,
    /// destroying it on <see cref="Dispose"/> after the world is destroyed.
    /// </summary>
    public World(ke_world_handle worldHandle, ke_scene_tree_handle treeHandle, IEcsRegistry ecs, IRuntime runtime)
    {
        _native       = worldHandle.@ref;
        _destroyWorld = worldHandle.destroy;
        _ownedTree    = treeHandle.@ref;
        _destroyTree  = treeHandle.destroy;
        Ecs           = ecs;
        Runtime       = runtime;
    }

    /// <summary>
    /// Managed wrapper over the scene tree embedded in this world. Created on
    /// first access and cached for the lifetime of the world.
    /// </summary>
    public SceneTree SceneTree
    {
        get
        {
            return _sceneTree ??= new SceneTree(_native->scene_tree(_native));
        }
    }

    /// <summary>
    /// Registers a managed apply callback for the given component id. The callback
    /// is invoked by the native scene loader whenever an
    /// <c>[entity.components.X]</c> block maps to <paramref name="cid"/>.
    /// </summary>
    /// <typeparam name="T">The unmanaged component struct the callback populates.</typeparam>
    /// <param name="cid">Component id returned by <c>IEcsRegistry.RegisterComponent</c>.</param>
    /// <param name="callback">Managed callback; must not be stored across frames.</param>
    public void RegisterComponentApply<T>(uint cid, ComponentApplyCallback<T> callback) where T : unmanaged
    {
        var bridge = new ApplyBridge<T>(callback);
        var del    = new ApplyNativeFn(bridge.Invoke);
        _applyHandles.Add(GCHandle.Alloc(del));

        var fnPtr = (delegate* unmanaged[Cdecl]<void*, ke_variant_table_entry*, uint, void>)
            Marshal.GetFunctionPointerForDelegate(del).ToPointer();

        KernelException.ThrowIfFailed(
            _native->register_component_apply(_native, cid, fnPtr, null).ToManaged());
    }

    private uint _scenePropertiesCid;

    /// <summary>
    /// Reads the <c>ke_scene_properties</c> component set by the scene loader for
    /// <paramref name="entity"/>. Returns false when the entity has no properties block.
    /// </summary>
    public unsafe bool TryGetProperties(ulong entity, out VariantReader reader)
    {
        if (_scenePropertiesCid == 0 &&
            !Ecs.TryLookupComponent("scene_properties", out _scenePropertiesCid))
        {
            reader = default;
            return false;
        }
        var sp = Ecs.GetComponent<ke_scene_properties>(entity, _scenePropertiesCid);
        if (sp.IsEmpty) { reader = default; return false; }
        reader = new VariantReader(sp[0].entries, sp[0].count);
        return true;
    }

    /// <inheritdoc cref="IDisposable.Dispose"/>
    public void Dispose()
    {
        if (_native is not null)
        {
            if (_destroyWorld != null) _destroyWorld(_native);
            _native = null;
        }
        if (_ownedTree is not null)
        {
            if (_destroyTree != null) _destroyTree(_ownedTree);
            _ownedTree = null;
        }
        foreach (var h in _applyHandles)
            if (h.IsAllocated) h.Free();
        _applyHandles.Clear();
    }

    // Non-generic delegate so Marshal.GetFunctionPointerForDelegate accepts it.
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private unsafe delegate void ApplyNativeFn(void* comp, ke_variant_table_entry* entries, uint count);

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

        internal unsafe void Invoke(void* comp, ke_variant_table_entry* entries, uint count)
        {
            var reader    = new VariantReader(entries, count);
            ref var typed = ref *(T*)comp;
            _callback(ref typed, in reader);
        }
    }
}
