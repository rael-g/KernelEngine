using System.Runtime.CompilerServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper around <c>ke_render_graph*</c>. Lets game / framework / plugin code add
/// render passes to the renderer's active chain without crossing the C ABI by hand.
/// </summary>
/// <remarks>
/// <para>
/// The graph itself is owned by the renderer that produced it (see <see cref="Renderer.GetRenderGraph"/>
/// for the active chain, or <see cref="Renderer.CreateRenderGraph"/> for a side graph). This wrapper
/// is therefore a view, not an owner — disposing it does not destroy the native graph. Disposing
/// the wrapper does release every <see cref="RenderPass"/> handed to it so the GC-anchored
/// trampoline state is freed deterministically.
/// </para>
/// <para>
/// Threading: passes must be added from the same thread that owns the renderer (ke.render).
/// Execution is automatic — the renderer calls <c>execute</c> every <c>SubmitPacket</c>.
/// </para>
/// </remarks>
public sealed unsafe class RenderGraph : IDisposable
{
    private ke_render_graph* _native;
    private readonly List<RenderPass> _ownedPasses = new();

    internal RenderGraph(ke_render_graph* native)
    {
        if (native is null) throw new ArgumentNullException(nameof(native));
        _native = native;
    }

    /// <summary>
    /// Adds <paramref name="pass"/> to the graph. The graph copies the pass's reads/writes
    /// arrays internally; the wrapper retains the <see cref="RenderPass"/> instance so its
    /// GC-pinned trampoline state (name buffers, callback delegate, GCHandle) stays alive
    /// for the graph's lifetime.
    /// </summary>
    public void AddPass(RenderPass pass)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        if (pass is null) throw new ArgumentNullException(nameof(pass));

        pass.BuildNativeParams(out ke_render_pass_params @params);
        var rc = _native->add_pass(_native, &@params, null);
        KernelException.ThrowIfFailed(rc.ToManaged());
        _ownedPasses.Add(pass);

        // Topology changed — the next Execute will recompile automatically. We
        // expose Recompile() as an explicit hook for callers that want to amortize
        // the cost (e.g., add 10 passes then compile once at the end).
    }

    /// <summary>
    /// Removes a pass by name. Returns <c>false</c> when no pass with that name is registered.
    /// The corresponding wrapper instance is disposed and dropped from the owned list.
    /// </summary>
    public bool RemovePass(string name)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        if (string.IsNullOrEmpty(name)) return false;

        var bytes = AsciiZ(name);
        ke_result rc;
        fixed (byte* p = bytes) rc = _native->remove_pass(_native, (sbyte*)p, null);
        if (rc != ke_result.KE_OK) return false;

        for (int i = _ownedPasses.Count - 1; i >= 0; i--) {
            if (_ownedPasses[i].Name == name) {
                _ownedPasses[i].Dispose();
                _ownedPasses.RemoveAt(i);
            }
        }
        return true;
    }

    /// <summary>
    /// Recomputes the topological order. Optional — Execute auto-compiles when the graph
    /// is dirty. Call this manually only to amortize the cost of multiple AddPass calls.
    /// </summary>
    public void Recompile()
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        KernelException.ThrowIfFailed(_native->compile(_native, null).ToManaged());
    }

    public void Dispose()
    {
        foreach (var p in _ownedPasses) p.Dispose();
        _ownedPasses.Clear();
        _native = null;
    }

    private static byte[] AsciiZ(string s)
    {
        var bytes = new byte[System.Text.Encoding.ASCII.GetByteCount(s) + 1];
        System.Text.Encoding.ASCII.GetBytes(s, 0, s.Length, bytes, 0);
        return bytes;
    }
}
