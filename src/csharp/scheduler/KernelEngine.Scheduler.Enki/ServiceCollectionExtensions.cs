
using KernelEngine.Scheduler.Enki.Native;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Scheduler.Enki;

/// <summary>Registers the enki-backed scheduler with a service collection.</summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a singleton <see cref="KernelEngine.Scheduler.Scheduler"/> created on first resolution.
    /// The enki library logs to the registered logger, or to stderr when there is none.
    /// </summary>
    /// <exception cref="InvalidOperationException">Thrown at resolution when the native factory fails.</exception>
    public static IServiceCollection AddEnkiScheduler(this IServiceCollection services)
    {
        services.AddSingleton<KernelEngine.Scheduler.Scheduler>(sp =>
        {
            unsafe
            {
                if (sp.GetService<KernelEngine.Logger.ILogger>() is { } logger)
                    KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_set_log_callback(KernelEngine.Logger.LogCallbackNative.Pointer, KernelEngine.Logger.LogCallbackNative.Pin(logger.Log));
                ke_scheduler_enki_params @params = default;
                ke_scheduler_handle handle;
                KernelEngine.NativeResults.ThrowIfFailed(
                    KernelEngine.Scheduler.Enki.Native.NativeMethods.scheduler_enki_create(&@params, &handle), "ke_scheduler_enki_create");
                return new KernelEngine.Scheduler.Scheduler(handle);
            }
        });

        return services;
    }
}
