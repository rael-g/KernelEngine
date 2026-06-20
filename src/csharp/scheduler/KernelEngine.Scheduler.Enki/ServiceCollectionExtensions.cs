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
                ke_error* err = null;
                var handle = KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_create(&err);
                if (handle.@ref == null) throw KernelError.FromNative(err, "scheduler_enki_create");
                return new KernelEngine.Kernel.Scheduler(handle);
            }
        });

        return services;
    }
}
