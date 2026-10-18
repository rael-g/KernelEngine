
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
    /// <summary>Creates the native scheduler with one worker per hardware thread besides the calling one.</summary>
    /// <exception cref="InvalidOperationException">The native factory returned no scheduler.</exception>
    public EnkiScheduler() : base(CreateNative(0))
    {
    }

    /// <summary>Creates the native scheduler with <paramref name="workerCount"/> workers besides the
    /// calling thread; 0 takes one per hardware thread.</summary>
    /// <exception cref="InvalidOperationException">The native factory returned no scheduler.</exception>
    public EnkiScheduler(uint workerCount) : base(CreateNative(workerCount))
    {
    }

    private static ke_scheduler_handle CreateNative(uint workerCount)
    {
        ke_scheduler_enki_params @params = default;
        @params.worker_count = workerCount;
        var handle = KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_create(&@params, null);
        if (handle.@ref == null)
            throw new InvalidOperationException("ke_scheduler_enki_create failed");
        return handle;
    }
}
