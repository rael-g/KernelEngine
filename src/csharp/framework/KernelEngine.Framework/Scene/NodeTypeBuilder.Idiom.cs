using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Framework.Native;

namespace KernelEngine.Framework;

/// <summary>
/// The one method kabic could not generate for <see cref="NodeTypeBuilder"/> —
/// see the <c>[idiom]</c> tag on <c>ke_node_type_builder.hook</c> in
/// <c>node_host.h</c>. <c>ke_node_hook_fn</c> is a raw C function pointer typedef
/// with no managed shape a generator can infer generically, so this marshals a
/// managed delegate through <see cref="UnmanagedCallersOnlyAttribute"/> by hand,
/// exactly the "GCHandle-pinned dispatcher lifetime management" the SDK design
/// (ScriptingArchitectureV2.md §6) always meant for hand-written glue, not codegen.
/// </summary>
public unsafe partial class NodeTypeBuilder
{
    /// <summary>
    /// One resolved archetype segment for a hook: <paramref name="entities"/> and
    /// <paramref name="columns"/> are parallel arrays of <paramref name="count"/>
    /// rows; <c>columns[i]</c> order matches the order <see cref="Access"/> was
    /// declared for this hook.
    /// </summary>
    public delegate void HookCallback(ReadOnlySpan<ulong> entities, void** columns, int count, float dt);

    // The native side holds only a GCHandle pointer (via ctx), never a managed
    // reference — this list is what keeps the callback (and its GCHandle) alive
    // for the node type's lifetime, which in v0 is the process lifetime: there is
    // no unregister/hot-reload path yet (see ke_node_host.commit's doc comment).
    private static readonly List<GCHandle> s_hookHandles = new();

    /// <summary>Declares a lifecycle hook and the managed callback it dispatches to.</summary>
    /// <returns>KE_NODE_HOOK_INVALID (0) if the builder is invalid.</returns>
    public uint Hook(NodeHookKind kind, HookCallback callback)
    {
        var gch = GCHandle.Alloc(callback);
        s_hookHandles.Add(gch);
        return Handle->hook(Handle, (ke_node_hook_kind)kind, &Trampoline, (void*)GCHandle.ToIntPtr(gch));
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static void Trampoline(void* ctx, ulong* entities, void** columns, nuint count, float dt)
    {
        var gch = GCHandle.FromIntPtr((nint)ctx);
        var callback = (HookCallback)gch.Target!;
        callback(new ReadOnlySpan<ulong>(entities, checked((int)count)), columns, checked((int)count), dt);
    }
}
