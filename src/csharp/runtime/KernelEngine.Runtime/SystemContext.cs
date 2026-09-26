using System.Runtime.InteropServices;

namespace KernelEngine.Runtime;

/// <summary>
/// Typed reads of a system context on top of <see cref="SystemCtx"/>: a component
/// attached from a value rather than from the byte pair the ABI takes, and the entities
/// of one resolved segment. A context of zero is accepted throughout — it means "outside
/// a system", and every operation answers the same way the native side does for it.
/// </summary>
public static unsafe class SystemContext
{
    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_system_ctx_attach", ExactSpelling = true)]
    private static extern byte ke_system_ctx_attach(void* ctx, ulong entity, uint cid,
                                                    void* data, nuint size);

    /// <summary>
    /// Deferred-attaches component <paramref name="cid"/> to <paramref name="entity"/>
    /// with <paramref name="value"/> as its data. The component is added at the wave
    /// barrier; the value is copied immediately so its lifetime need not extend past
    /// this call. Returns false if no context (0) or on allocation failure — the
    /// caller then falls back to its immediate path.
    /// </summary>
    public static bool Attach<T>(nint ctx, ulong entity, uint cid, in T value) where T : unmanaged
    {
        fixed (T* p = &value)
            return ke_system_ctx_attach((void*)ctx, entity, cid, p, (nuint)sizeof(T)) != 0;
    }

    /// <summary>
    /// How many archetype segments the system's query at <paramref name="queryIndex"/>
    /// resolved to this tick. Zero for a system that declared no query, so a caller
    /// needs no separate test for that case.
    /// </summary>
    public static int SegmentCount(nint ctx, uint queryIndex = 0) =>
        SystemCtx.View(ctx, queryIndex).Length;

    /// <summary>
    /// The entities of one resolved segment, in storage order. Valid only for the
    /// duration of the system body — the segment points straight at ECS memory, which
    /// the wave barrier is free to move afterwards.
    /// </summary>
    public static ReadOnlySpan<ulong> EntitiesOf(nint ctx, uint queryIndex, int segment)
    {
        var segments = SystemCtx.View(ctx, queryIndex);
        if (segment < 0 || segment >= segments.Length) return default;
        ref readonly var s = ref segments[segment];
        return s.entities == null ? default : new ReadOnlySpan<ulong>(s.entities, (int)s.count);
    }
}
