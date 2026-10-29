
using KernelEngine.TaskPool.Enki.Native;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.TaskPool.Enki;

/// <summary>Registers the enki-backed task pool with a service collection.</summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a singleton <see cref="KernelEngine.TaskPool.TaskPool"/> created on first resolution.
    /// The enki library logs to the registered logger, or to stderr when there is none.
    /// </summary>
    /// <exception cref="InvalidOperationException">Thrown at resolution when the native factory fails.</exception>
    public static IServiceCollection AddEnkiTaskPool(this IServiceCollection services)
    {
        services.AddSingleton<KernelEngine.TaskPool.TaskPool>(sp =>
        {
            unsafe
            {
                if (sp.GetService<KernelEngine.Logger.ILogger>() is { } logger)
                    KernelEngine.TaskPool.Enki.Native.NativeMethods.task_pool_enki_set_log_callback(KernelEngine.Logger.LogCallbackNative.Pointer, KernelEngine.Logger.LogCallbackNative.Pin(logger.Log));
                ke_task_pool_enki_params @params = default;
                ke_task_pool_handle handle;
                KernelEngine.NativeResults.ThrowIfFailed(
                    KernelEngine.TaskPool.Enki.Native.NativeMethods.task_pool_enki_create(&@params, &handle), "ke_task_pool_enki_create");
                return new KernelEngine.TaskPool.TaskPool(handle);
            }
        });

        return services;
    }
}
