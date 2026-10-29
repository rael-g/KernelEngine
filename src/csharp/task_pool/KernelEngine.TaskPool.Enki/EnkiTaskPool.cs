
using KernelEngine.Common.Native;
using KernelEngine.TaskPool.Enki.Native;

namespace KernelEngine.TaskPool.Enki;

/// <summary>
/// DI-friendly enki-backed task pool. The constructor builds the native
/// task pool internally; consumers register it via
/// <c>services.Add&lt;ITaskPool, EnkiTaskPool&gt;()</c>.
/// </summary>
public sealed unsafe class EnkiTaskPool : KernelEngine.TaskPool.TaskPool
{
    /// <summary>Creates the native task pool with one worker per hardware thread besides the calling one.</summary>
    /// <exception cref="OutOfMemoryException">The native factory could not allocate the task pool.</exception>
    /// <exception cref="InvalidOperationException">The native factory could not create the pool.</exception>
    public EnkiTaskPool() : base(CreateNative(0))
    {
    }

    /// <summary>Creates the native task pool with <paramref name="workerCount"/> workers besides the
    /// calling thread; 0 takes one per hardware thread.</summary>
    /// <exception cref="OutOfMemoryException">The native factory could not allocate the task pool.</exception>
    /// <exception cref="InvalidOperationException">The native factory could not create the pool.</exception>
    public EnkiTaskPool(uint workerCount) : base(CreateNative(workerCount))
    {
    }

    /// <summary>Creates the native task pool with one worker per hardware thread besides the calling
    /// one, the enki library logging to <paramref name="logger"/>.</summary>
    /// <exception cref="OutOfMemoryException">The native factory could not allocate the task pool.</exception>
    /// <exception cref="InvalidOperationException">The native factory could not create the pool.</exception>
    public EnkiTaskPool(KernelEngine.Logger.ILogger logger) : base(CreateNative(0, logger))
    {
    }

    private static ke_task_pool_handle CreateNative(uint workerCount, KernelEngine.Logger.ILogger? logger = null)
    {
        if (logger is not null)
            KernelEngine.TaskPool.Enki.Native.NativeMethods.task_pool_enki_set_log_callback(KernelEngine.Logger.LogCallbackNative.Pointer, KernelEngine.Logger.LogCallbackNative.Pin(logger.Log));
        ke_task_pool_enki_params @params = default;
        @params.worker_count = workerCount;
        ke_task_pool_handle handle;
        KernelEngine.NativeResults.ThrowIfFailed(
            KernelEngine.TaskPool.Enki.Native.NativeMethods.task_pool_enki_create(&@params, &handle), "ke_task_pool_enki_create");
        return handle;
    }
}
