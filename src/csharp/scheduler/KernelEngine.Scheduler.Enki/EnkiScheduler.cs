using KernelEngine.Kernel;
using KernelEngine.Common.Native;
using KernelEngine.Scheduler.Enki.Native;

namespace KernelEngine.Scheduler.Enki;

/// <summary>
/// DI-friendly enki-backed scheduler. The constructor builds the native
/// scheduler internally; consumers register it via
/// <c>services.Add&lt;IScheduler, EnkiScheduler&gt;()</c>.
/// </summary>
/// <remarks>
/// Inherits from <see cref="KernelEngine.Kernel.Scheduler"/> so all
/// existing managed APIs (DispatchKernelTask, async Task overloads) stay
/// available without duplication. The native lifecycle is owned by this
/// instance — destroy happens in the inherited Dispose.
/// </remarks>
public sealed unsafe class EnkiScheduler : KernelEngine.Kernel.Scheduler
{
    public EnkiScheduler() : base(CreateNative())
    {
    }

    private static ke_scheduler_handle CreateNative()
    {
        ke_scheduler_handle handle;
        var rc = KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_create(&handle, null);
        if (rc != ke_result.KE_OK)
            throw new InvalidOperationException($"ke_scheduler_enki_create failed: {rc}");
        return handle;
    }
}
