using KernelEngine.Kernel.Native;
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
                var logger = sp.GetService<Logger>();
                var @params = new Native.ke_asset_loader_assimp_params
                {
                    allocator = sp.GetRequiredService<Allocator>().Native,
                    logger    = logger != null ? logger.Native : null,
                };
                ke_asset_loader* native;
                KernelException.ThrowIfFailed(Native.NativeMethods.asset_loader_assimp_create(&@params, &native).ToManaged());
                return new AssetLoader(native, sp.GetRequiredService<KernelEngine.Kernel.TaskScheduler>());
            }
        });

        return services;
    }
}
