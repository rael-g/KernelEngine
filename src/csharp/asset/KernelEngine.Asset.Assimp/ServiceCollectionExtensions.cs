using KernelEngine.Common.Native;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Scheduler;
using KernelEngine.Logger;

namespace KernelEngine.Asset.Assimp;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers an Assimp-backed <see cref="IAssetLoader"/> singleton.
    /// </summary>
    public static IServiceCollection AddAssimpAssetLoader(this IServiceCollection services)
    {
        services.AddSingleton<IAssetLoader>(sp =>
        {
            unsafe
            {
                var logger = sp.GetService<INativeLogger>();
                var @params = new Native.ke_asset_loader_assimp_params
                {
                    logger = logger != null ? logger.Native : null,
                };
                ke_error* err = null;
                var handle = Native.NativeMethods.asset_loader_assimp_create(&@params, &err);
                if (handle.@ref == null) throw KernelError.FromNative(err, "asset_loader_assimp_create");
                // Async loading uses the kernel scheduler; resolve via the
                // interface so any IScheduler impl (EnkiScheduler,
                // future alternatives) works. The concrete base class is
                // KernelEngine.Scheduler.Scheduler which both impls inherit.
                var scheduler = (KernelEngine.Scheduler.Scheduler)sp.GetRequiredService<IScheduler>();
                return new AssetLoader(handle, scheduler);
            }
        });

        return services;
    }
}
