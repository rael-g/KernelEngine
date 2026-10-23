
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
    /// <exception cref="OutOfMemoryException">The native factory could not allocate the scheduler.</exception>
    /// <exception cref="InvalidOperationException">The native factory could not create the pool.</exception>
    public EnkiScheduler() : base(CreateNative(0))
    {
    }

    /// <summary>Creates the native scheduler with <paramref name="workerCount"/> workers besides the
    /// calling thread; 0 takes one per hardware thread.</summary>
    /// <exception cref="OutOfMemoryException">The native factory could not allocate the scheduler.</exception>
    /// <exception cref="InvalidOperationException">The native factory could not create the pool.</exception>
    public EnkiScheduler(uint workerCount) : base(CreateNative(workerCount))
    {
    }

    /// <summary>Creates the native scheduler with one worker per hardware thread besides the calling
    /// one, the enki library logging to <paramref name="logger"/>.</summary>
    /// <exception cref="OutOfMemoryException">The native factory could not allocate the scheduler.</exception>
    /// <exception cref="InvalidOperationException">The native factory could not create the pool.</exception>
    public EnkiScheduler(KernelEngine.Logger.ILogger logger) : base(CreateNative(0, logger))
    {
    }

    private static ke_scheduler_handle CreateNative(uint workerCount, KernelEngine.Logger.ILogger? logger = null)
    {
        if (logger is not null)
            KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_set_log_callback(KernelEngine.Logger.LogCallbackNative.Pointer, KernelEngine.Logger.LogCallbackNative.Pin(logger.Log));
        ke_scheduler_enki_params @params = default;
        @params.worker_count = workerCount;
        ke_scheduler_handle handle;
        KernelEngine.NativeResults.ThrowIfFailed(
            KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_create(&@params, &handle), "ke_scheduler_enki_create");
        return handle;
    }
}
