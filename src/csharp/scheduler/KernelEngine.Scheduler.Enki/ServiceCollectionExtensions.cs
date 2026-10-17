
using KernelEngine.Common.Native;
using KernelEngine.Scheduler.Enki.Native;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Scheduler.Enki;

/// <summary>Registers the enki-backed scheduler with a service collection.</summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a singleton <see cref="KernelEngine.Scheduler.Scheduler"/> created on first resolution.
    /// </summary>
    /// <exception cref="InvalidOperationException">Thrown at resolution when the native factory fails.</exception>
    public static IServiceCollection AddEnkiScheduler(this IServiceCollection services)
    {
        services.AddSingleton<KernelEngine.Scheduler.Scheduler>(sp =>
        {
            unsafe
            {
                ke_error* err = null;
                ke_scheduler_enki_params @params = default;
                var handle = KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_create(&@params, &err);
                if (handle.@ref == null) throw NativeErrors.FromNative(err, "scheduler_enki_create");
                return new KernelEngine.Scheduler.Scheduler(handle);
            }
        });

        return services;
    }
}
