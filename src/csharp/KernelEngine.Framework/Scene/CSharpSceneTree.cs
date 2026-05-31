using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Tier S round-trip implementation of <c>ke_scene_tree</c>.
/// <para>
/// Delegates to <see cref="Tree"/> (the existing C# scene graph) while wiring the native vtable
/// so non-.NET callers (e.g. Lua, C++) can perform node lookup and destruction through the C ABI.
/// The lifecycle tick_* methods are intentionally absent from the contract: native bindings drive
/// lifecycle through <c>ke_script_component</c> callbacks (S1), not C# tree walks.
/// </para>
/// </summary>
internal sealed unsafe class CSharpSceneTree : IDisposable
{
    private ke_scene_tree* _native;
    private GCHandle _selfHandle;
    private bool _disposed;

    private readonly Tree _tree;

    private const ulong KE_ENTITY_INVALID = 0;

    public CSharpSceneTree(Tree tree)
    {
        _tree       = tree;
        _selfHandle = GCHandle.Alloc(this);

        _native = (ke_scene_tree*)NativeMemory.Alloc((nuint)sizeof(ke_scene_tree));
        *_native = new ke_scene_tree
        {
            handle       = (void*)GCHandle.ToIntPtr(_selfHandle),
            root         = &NativeRoot,
            destroy_node = &NativeDestroyNode,
            destroy_all  = &NativeDestroyAll,
            find_node    = &NativeFindNode,
            destroy      = &NativeDestroy,
        };
    }

    public ke_scene_tree* Native => _native;

    // ── Trampolines ───────────────────────────────────────────────────────────

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ulong NativeRoot(ke_scene_tree* self)
    {
        var bridge = (CSharpSceneTree)GCHandle.FromIntPtr((nint)self->handle).Target!;
        return bridge._tree.Root.Entity;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeDestroyNode(ke_scene_tree* self, ulong entity)
    {
        try
        {
            var bridge = (CSharpSceneTree)GCHandle.FromIntPtr((nint)self->handle).Target!;
            var node   = Node.FromEntity(entity);
            if (node == null) return ke_result.KE_ERROR_NOT_FOUND;
            bridge._tree.DestroyNode(node);
            return ke_result.KE_OK;
        }
        catch
        {
            return ke_result.KE_ERROR;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeDestroyAll(ke_scene_tree* self)
    {
        var bridge = (CSharpSceneTree)GCHandle.FromIntPtr((nint)self->handle).Target!;
        bridge._tree.DestroyAll();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ulong NativeFindNode(ke_scene_tree* self, sbyte* nameOrPath)
    {
        var bridge = (CSharpSceneTree)GCHandle.FromIntPtr((nint)self->handle).Target!;
        var path   = Marshal.PtrToStringUTF8((nint)nameOrPath);
        if (path == null) return KE_ENTITY_INVALID;
        return bridge._tree.FindNode(path)?.Entity ?? KE_ENTITY_INVALID;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeDestroy(ke_scene_tree* self) { /* managed via IDisposable */ }

    // ── IDisposable ───────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_native != null) { NativeMemory.Free(_native); _native = null; }
        if (_selfHandle.IsAllocated) _selfHandle.Free();
    }
}
