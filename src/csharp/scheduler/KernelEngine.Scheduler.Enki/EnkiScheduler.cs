
using KernelEngine.Common.Native;
using KernelEngine.Scheduler.Enki.Native;

namespace KernelEngine.Scheduler.Enki;

/// <summary>
/// DI-friendly enki-backed scheduler. The constructor builds the native
/// scheduler internally; consumers register it via
/// <c>services.Add&lt;IScheduler, EnkiScheduler&gt;()</c>.
/// </summary>
public sealed unsafe class EnkiScheduler : KernelEngine.Scheduler.Scheduler
{
    /// <summary>Creates the native scheduler.</summary>
    /// <exception cref="InvalidOperationException">The native factory returned no scheduler.</exception>
    public EnkiScheduler() : base(CreateNative())
    {
    }

    private static ke_scheduler_handle CreateNative()
    {
        ke_scheduler_enki_params @params = default;
        var handle = KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_create(&@params, null);
        if (handle.@ref == null)
            throw new InvalidOperationException("ke_scheduler_enki_create failed");
        return handle;
    }
}
