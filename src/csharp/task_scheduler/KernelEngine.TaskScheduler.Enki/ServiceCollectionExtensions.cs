using System.Runtime.InteropServices;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.TaskScheduler.Enki;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddEnkiTaskScheduler(this IServiceCollection services)
    {
        services.AddSingleton<KernelEngine.Kernel.TaskScheduler>(sp =>
        {
            var allocator = sp.GetRequiredService<Allocator>();
            
            unsafe
            {
                ke_task_scheduler* nativeScheduler;
                KernelException.ThrowIfFailed(KernelEngine.TaskScheduler.Enki.Native.NativeMethods.task_scheduler_enki_create(allocator.Native, &nativeScheduler, null).ToManaged());
                return new KernelEngine.Kernel.TaskScheduler(nativeScheduler);
            }
        });
        
        return services;
    }
}
