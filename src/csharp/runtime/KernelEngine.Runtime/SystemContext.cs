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
}
