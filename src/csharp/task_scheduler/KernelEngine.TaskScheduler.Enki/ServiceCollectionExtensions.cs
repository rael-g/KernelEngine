using System.Runtime.InteropServices;
using KernelEngine.Kernel;
using KernelEngine.Common.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.TaskScheduler.Enki;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddEnkiTaskScheduler(this IServiceCollection services)
    {
        services.AddSingleton<KernelEngine.Kernel.TaskScheduler>(sp =>
        {
            unsafe
            {
                ke_task_scheduler_handle handle;
                KernelException.ThrowIfFailed(KernelEngine.TaskScheduler.Enki.Native.NativeMethods.task_scheduler_enki_create(&handle, null).ToManaged());
                return new KernelEngine.Kernel.TaskScheduler(handle);
            }
        });
        
        return services;
    }
}
