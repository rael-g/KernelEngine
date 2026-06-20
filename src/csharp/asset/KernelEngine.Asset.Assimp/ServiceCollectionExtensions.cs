using KernelEngine.Common.Native;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Asset.Assimp;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers an Assimp-backed <see cref="IAssetLoader"/> singleton.
    /// Requires <c>AddKernel()</c> to be called first.
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
                // KernelEngine.Kernel.Scheduler which both impls inherit.
                var scheduler = (KernelEngine.Kernel.Scheduler)sp.GetRequiredService<IScheduler>();
                return new AssetLoader(handle, scheduler);
            }
        });

        return services;
    }
}
