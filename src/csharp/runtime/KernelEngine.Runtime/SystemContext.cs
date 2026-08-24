using System.Runtime.InteropServices;

namespace KernelEngine.Runtime;

/// <summary>
/// Managed entry points for the native system-context deferred-mutation API
/// (<c>ke_system_ctx_*</c>). The context pointer is handed to a system's callback
/// each tick (as an <see cref="nint"/>); these helpers forward structural changes
/// to the runtime's per-wave defer queue, applied serially at the wave barrier
/// where entity creation and archetype moves are legal. A zero context is treated
/// as "outside a system" and the call is a no-op returning failure — callers use
/// their immediate path instead.
/// </summary>
public static unsafe class SystemContext
{
    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_system_ctx_attach", ExactSpelling = true)]
    private static extern byte ke_system_ctx_attach(void* ctx, ulong entity, uint cid,
                                                    void* data, nuint size);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_system_ctx_reserve", ExactSpelling = true)]
    private static extern ulong ke_system_ctx_reserve(void* ctx);

    /// <summary>
    /// Deferred-attaches component <paramref name="cid"/> to <paramref name="entity"/>
    /// with <paramref name="value"/> as its data. The component is added at the wave
    /// barrier; the value is copied immediately so its lifetime need not extend past
    /// this call. Returns false if no context (0) or on allocation failure — the
    /// caller then falls back to its immediate path.
    /// </summary>
    public static bool Attach<T>(nint ctx, ulong entity, uint cid, in T value) where T : unmanaged
    {
        if (ctx == 0) return false;
        fixed (T* p = &value)
            return ke_system_ctx_attach((void*)ctx, entity, cid, p, (nuint)sizeof(T)) != 0;
    }

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_system_ctx_slice", ExactSpelling = true)]
    private static extern void ke_system_ctx_slice(void* ctx, uint* outIndex, uint* outCount);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_system_ctx_view", ExactSpelling = true)]
    private static extern KernelEngine.Ecs.Native.ke_ecs_segment* ke_system_ctx_view(
        void* ctx, uint queryIndex, nuint* outCount);

    /// <summary>
    /// How many archetype segments the system's query at <paramref name="queryIndex"/>
    /// resolved to this tick. Zero for a system that declared no query, so a caller
    /// needs no separate test for that case.
    /// </summary>
    public static int SegmentCount(nint ctx, uint queryIndex = 0)
    {
        if (ctx == 0) return 0;
        nuint count = 0;
        return ke_system_ctx_view((void*)ctx, queryIndex, &count) == null ? 0 : (int)count;
    }

    /// <summary>
    /// The entities of one resolved segment, in storage order. Valid only for the
    /// duration of the system body — the segment points straight at ECS memory, which
    /// the wave barrier is free to move afterwards.
    /// </summary>
    public static ReadOnlySpan<ulong> EntitiesOf(nint ctx, uint queryIndex, int segment)
    {
        if (ctx == 0) return default;
        nuint count = 0;
        var segments = ke_system_ctx_view((void*)ctx, queryIndex, &count);
        if (segments == null || segment < 0 || (nuint)segment >= count) return default;
        ref var s = ref segments[segment];
        return s.entities == null ? default : new ReadOnlySpan<ulong>(s.entities, (int)s.count);
    }

    /// <summary>
    /// Reports which share of its entity set this body call owns: the index is in
    /// [0, count). A system the runtime chose not to slice — including anything
    /// running outside a system — reports index 0 of count 1, so a caller written
    /// against this reads the whole set without asking whether it was sliced.
    /// </summary>
    public static void Slice(nint ctx, out uint index, out uint count)
    {
        index = 0;
        count = 1;
        if (ctx == 0) return;
        fixed (uint* i = &index)
        fixed (uint* c = &count)
            ke_system_ctx_slice((void*)ctx, i, c);
    }

    /// <summary>
    /// Reserves a real, usable entity id immediately — safe to call from a wave
    /// thread, unlike <c>entity_create</c>. Components attach at the wave barrier
    /// via <see cref="Attach{T}"/>. Returns 0 (KE_ENTITY_INVALID) if no context.
    /// </summary>
    public static ulong Reserve(nint ctx)
    {
        if (ctx == 0) return 0;
        return ke_system_ctx_reserve((void*)ctx);
    }
}
