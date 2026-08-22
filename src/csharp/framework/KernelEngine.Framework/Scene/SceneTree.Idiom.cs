namespace KernelEngine.Framework;

/// <summary>
/// The parts of <see cref="SceneTree"/> that are not a direct image of the C ABI: the
/// <c>nint</c>-typed <c>systemCtx</c> overloads (so callers stay free of <c>unsafe</c>
/// pointer syntax at the call site, matching every other <c>ke_system_ctx*</c> boundary
/// in the framework), and the <see cref="Root"/> property. Everything that mirrors the
/// vtable 1:1 is generated in <c>Generated/SceneTree.g.cs</c>.
/// </summary>
public unsafe partial class SceneTree
{
    /// <summary>Root entity. Always valid for the lifetime of the tree.</summary>
    public ulong Root
    {
        get
        {
            var native = ((INativeSceneTree)this).Native;
            return native->root(native);
        }
    }

    /// <summary>
    /// Creates a new node attached under <paramref name="parent"/>
    /// (<c>0</c> = root). When called from inside a running system, pass the
    /// system context (<paramref name="systemCtx"/>) so the structural change is
    /// deferred to the wave barrier; pass <c>default</c> for immediate creation.
    /// </summary>
    public ulong CreateNode(string name, ulong parent = 0, nint systemCtx = default)
        => CreateNode(name, parent, (KernelEngine.Runtime.Native.ke_system_ctx*)systemCtx);

    /// <summary>
    /// Destroys a node and all its descendants. Fires on_destroy hooks in
    /// post-order (children before parents). When called from inside a running
    /// system, pass the system context (<paramref name="systemCtx"/>) so the
    /// teardown is deferred to the wave barrier; pass <c>default</c> for immediate.
    /// </summary>
    public void DestroyNode(ulong entity, nint systemCtx = default)
        => DestroyNode(entity, (KernelEngine.Runtime.Native.ke_system_ctx*)systemCtx);
}
