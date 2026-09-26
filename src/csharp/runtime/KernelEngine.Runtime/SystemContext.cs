namespace KernelEngine.Runtime;

/// <summary>
/// Typed reads of a system context on top of <see cref="SystemCtx"/>: how many segments a
/// query resolved to, and the entities of one of them. A context of zero is accepted
/// throughout — it means "outside a system", and every operation answers the same way the
/// native side does for it.
/// </summary>
public static unsafe class SystemContext
{
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
