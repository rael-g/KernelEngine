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
                ke_asset_loader_handle handle;
                KernelException.ThrowIfFailed(Native.NativeMethods.asset_loader_assimp_create(&@params, &handle, null).ToManaged());
                // Async loading uses the kernel scheduler; resolve via the
                // interface so any ITaskScheduler impl (EnkiTaskScheduler,
                // future alternatives) works. The concrete base class is
                // KernelEngine.Kernel.TaskScheduler which both impls inherit.
                var scheduler = (KernelEngine.Kernel.TaskScheduler)sp.GetRequiredService<ITaskScheduler>();
                return new AssetLoader(handle, scheduler);
            }
        });

        return services;
    }
}
