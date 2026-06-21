using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Common.Native;

namespace KernelEngine.Render;

/// <summary>
/// Kind of work a pass performs. Mirrors <c>ke_pass_type</c>.
/// </summary>
public enum PassType
{
    Geometry   = 0,
    Fullscreen = 1,
    Compute    = 2,
}

/// <summary>
/// How a pass accesses a declared resource. Mirrors <c>ke_resource_access</c>.
/// </summary>
public enum ResourceAccess
{
    None             = 0,
    Sampled          = 1,
    ColorAttachment  = 2,
    DepthAttachment  = 3,
    StorageRead      = 4,
    StorageWrite     = 5,
    StorageReadWrite = 6,
}

/// <summary>
/// One unit of work in a <see cref="RenderGraph"/>. Built fluently then handed to
/// <see cref="RenderGraph.AddPass"/>; the graph copies the data into native memory and
/// owns the lifecycle thereafter. The <see cref="OnRecord"/> callback runs on ke.render
/// every frame; do not allocate or take long-running locks inside it.
/// </summary>
public sealed unsafe class RenderPass : IDisposable
{
    private readonly List<(string Name, ResourceAccess Access)> _reads = new(2);
    private readonly List<(string Name, ResourceAccess Access)> _writes = new(2);
    private Action<RenderPassContext>? _record;

    // Pinned ASCII storage for resource names + the pass name. Lifetimes match the
    // RenderPass instance; the native graph copies the arrays internally, but the
    // name pointers are borrowed — we have to outlive AddPass.
    private GCHandle _selfHandle;
    private byte[]? _pinnedNameBytes;
    private byte[]? _pinnedReadNameBytes;   // concatenated, null-terminated
    private byte[]? _pinnedWriteNameBytes;
    private ke_resource_ref[]? _pinnedReadRefs;
    private ke_resource_ref[]? _pinnedWriteRefs;

    public string Name { get; }
    public PassType Type { get; set; } = PassType.Geometry;

    public RenderPass(string name)
    {
        if (string.IsNullOrEmpty(name))
            throw new ArgumentException("Pass name must be non-empty.", nameof(name));
        Name = name;
    }

    public RenderPass Reads(string resourceName, ResourceAccess access = ResourceAccess.Sampled)
    {
        _reads.Add((resourceName, access));
        return this;
    }

    public RenderPass Writes(string resourceName, ResourceAccess access = ResourceAccess.ColorAttachment)
    {
        _writes.Add((resourceName, access));
        return this;
    }

    public RenderPass WithType(PassType type)
    {
        Type = type;
        return this;
    }

    /// <summary>Sets the per-frame record callback. Required before adding to a graph.</summary>
    public RenderPass OnRecord(Action<RenderPassContext> record)
    {
        _record = record ?? throw new ArgumentNullException(nameof(record));
        return this;
    }

    // ── Internal: materialise the native ke_render_pass_params + keep the pinning alive ──

    public void BuildNativeParams(out ke_render_pass_params @params)
    {
        if (_record is null)
            throw new InvalidOperationException($"RenderPass '{Name}' has no OnRecord callback.");
        if (_selfHandle.IsAllocated)
            throw new InvalidOperationException($"RenderPass '{Name}' is already attached to a graph.");

        _selfHandle = GCHandle.Alloc(this);

        _pinnedNameBytes  = AsciiZ(Name);
        _pinnedReadRefs   = PackRefs(_reads,  out _pinnedReadNameBytes);
        _pinnedWriteRefs  = PackRefs(_writes, out _pinnedWriteNameBytes);

        @params = default;
        @params.name        = (sbyte*)Unsafe.AsPointer(ref _pinnedNameBytes[0]);
        @params.type        = (ke_pass_type)(int)Type;
        @params.reads       = _pinnedReadRefs.Length  > 0 ? (ke_resource_ref*)Unsafe.AsPointer(ref _pinnedReadRefs[0])  : null;
        @params.reads_count = (uint)_pinnedReadRefs.Length;
        @params.writes       = _pinnedWriteRefs.Length > 0 ? (ke_resource_ref*)Unsafe.AsPointer(ref _pinnedWriteRefs[0]) : null;
        @params.writes_count = (uint)_pinnedWriteRefs.Length;
        @params.record       = &RecordTrampoline;
        @params.user         = (void*)GCHandle.ToIntPtr(_selfHandle);
    }

    /// <summary>Single static native trampoline for every C# pass — finds the right
    /// instance via the GCHandle stored in <c>user</c> and dispatches to its delegate.</summary>
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static void RecordTrampoline(ke_render_pass_ctx* ctx, void* user)
    {
        if (user is null) return;
        var handle = GCHandle.FromIntPtr((IntPtr)user);
        if (handle.Target is not RenderPass pass || pass._record is null) return;
        try
        {
            pass._record(new RenderPassContext(ctx));
        }
        catch
        {
            // The native graph executor has no way to propagate a managed exception
            // back to the caller of SubmitPacket, so we swallow here to avoid
            // crossing the ABI boundary unwinding. Logging is left to the callback
            // owner (the engine logger isn't reachable from this context).
        }
    }

    public void Dispose()
    {
        if (_selfHandle.IsAllocated) _selfHandle.Free();
        _pinnedNameBytes = null;
        _pinnedReadNameBytes = null;
        _pinnedWriteNameBytes = null;
        _pinnedReadRefs = null;
        _pinnedWriteRefs = null;
    }

    // ── ASCII packing helpers ─────────────────────────────────────────────────

    private static byte[] AsciiZ(string s)
    {
        var bytes = new byte[System.Text.Encoding.ASCII.GetByteCount(s) + 1];
        System.Text.Encoding.ASCII.GetBytes(s, 0, s.Length, bytes, 0);
        return bytes;
    }

    private static ke_resource_ref[] PackRefs(List<(string Name, ResourceAccess Access)> src, out byte[] nameStorage)
    {
        if (src.Count == 0) { nameStorage = Array.Empty<byte>(); return Array.Empty<ke_resource_ref>(); }
        // One contiguous null-terminated string per ref; the refs hold pointers into the same array.
        int totalBytes = 0;
        foreach (var (n, _) in src) totalBytes += System.Text.Encoding.ASCII.GetByteCount(n) + 1;
        nameStorage = new byte[totalBytes];
        var refs = new ke_resource_ref[src.Count];
        int offset = 0;
        for (int i = 0; i < src.Count; i++) {
            var n = src[i].Name;
            int written = System.Text.Encoding.ASCII.GetBytes(n, 0, n.Length, nameStorage, offset);
            refs[i].name   = (sbyte*)Unsafe.AsPointer(ref nameStorage[offset]);
            refs[i].access = (ke_resource_access)(int)src[i].Access;
            offset += written;
            nameStorage[offset] = 0;
            offset += 1;
        }
        return refs;
    }
}
