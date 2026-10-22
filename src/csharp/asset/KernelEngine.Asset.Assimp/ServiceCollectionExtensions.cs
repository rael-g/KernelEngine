using KernelEngine.Common.Native;
using KernelEngine.Logger;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Asset.Assimp;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers an Assimp-backed <see cref="IAssetLoader"/> singleton. The library logs to the
    /// registered <see cref="ILogger"/>, or to stderr when there is none.
    /// </summary>
    public static IServiceCollection AddAssimpAssetLoader(this IServiceCollection services)
    {
        services.AddSingleton<IAssetLoader>(sp =>
        {
            unsafe
            {
                if (sp.GetService<ILogger>() is { } logger)
                    Native.NativeMethods.asset_assimp_set_log_callback(LogCallbackNative.Pointer, LogCallbackNative.Pin(logger.Log));
                ke_error* err = null;
                var handle = Native.NativeMethods.asset_loader_assimp_create(&err);
                if (handle.@ref == null) throw NativeErrors.FromNative(err, "asset_loader_assimp_create");
                return new AssetLoader(handle);
            }
        });

        return services;
    }
}
