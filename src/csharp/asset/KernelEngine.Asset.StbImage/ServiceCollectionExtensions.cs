using KernelEngine.Logger;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Asset.StbImage;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers an stb_image-backed <see cref="IImageLoader"/> singleton, and the
    /// same loader as <see cref="INativeImageLoader"/>. The library logs to the registered
    /// <see cref="ILogger"/>, or to stderr when there is none.
    /// </summary>
    public static IServiceCollection AddStbImageLoader(this IServiceCollection services)
    {
        services.AddSingleton<IImageLoader>(sp =>
        {
            unsafe
            {
                if (sp.GetService<ILogger>() is { } logger)
                    Native.NativeMethods.asset_stb_image_set_log_callback(LogCallbackNative.Pointer, LogCallbackNative.Pin(logger.Log));
                KernelEngine.Asset.Native.ke_image_loader_handle handle;
                KernelEngine.NativeResults.ThrowIfFailed(Native.NativeMethods.image_loader_stb_create(&handle), "ke_image_loader_stb_create");
                return new ImageLoader(handle);
            }
        });
        services.AddSingleton<INativeImageLoader>(sp => (ImageLoader)sp.GetRequiredService<IImageLoader>());
        return services;
    }
}
