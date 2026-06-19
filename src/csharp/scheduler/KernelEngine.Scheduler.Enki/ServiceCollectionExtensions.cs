using KernelEngine.Kernel;
using KernelEngine.Common.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Scheduler.Enki;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddEnkiScheduler(this IServiceCollection services)
    {
        services.AddSingleton<KernelEngine.Kernel.Scheduler>(sp =>
        {
            unsafe
            {
                ke_scheduler_handle handle;
                KernelException.ThrowIfFailed(KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_create(&handle, null).ToManaged());
                return new KernelEngine.Kernel.Scheduler(handle);
            }
        });

        return services;
    }
}
