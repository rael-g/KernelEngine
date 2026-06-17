using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.TaskScheduler.Enki.Native;

namespace KernelEngine.TaskScheduler.Enki;

/// <summary>
/// DI-friendly enki-backed task scheduler. The constructor builds the native
/// scheduler internally using the injected <see cref="Allocator"/>; consumers
/// register it via <c>services.Add&lt;ITaskScheduler, EnkiTaskScheduler&gt;()</c>
/// and the container resolves the rest.
/// </summary>
/// <remarks>
/// Inherits from <see cref="KernelEngine.Kernel.TaskScheduler"/> so all
/// existing managed APIs (DispatchKernelTask, async Task overloads) stay
/// available without duplication. The native lifecycle is owned by this
/// instance — destroy happens in the inherited Dispose.
/// </remarks>
public sealed unsafe class EnkiTaskScheduler : KernelEngine.Kernel.TaskScheduler
{
    public EnkiTaskScheduler(Allocator allocator) : base(CreateNative(allocator))
    {
    }

    private static ke_task_scheduler* CreateNative(Allocator allocator)
    {
        ArgumentNullException.ThrowIfNull(allocator);
        ke_task_scheduler* native;
        var rc = KernelEngine.TaskScheduler.Enki.Native.NativeMethods.task_scheduler_enki_create(allocator.Native, &native, null);
        if (rc != ke_result.KE_OK)
            throw new InvalidOperationException($"ke_task_scheduler_enki_create failed: {rc}");
        return native;
    }
}
