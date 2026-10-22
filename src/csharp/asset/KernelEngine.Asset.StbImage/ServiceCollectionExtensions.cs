using KernelEngine.Common.Native;
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
                ke_error* err = null;
                var handle = Native.NativeMethods.image_loader_stb_create(&err);
                if (handle.@ref == null) throw NativeErrors.FromNative(err, "image_loader_stb_create");
                return new ImageLoader(handle);
            }
        });
        services.AddSingleton<INativeImageLoader>(sp => (ImageLoader)sp.GetRequiredService<IImageLoader>());
        return services;
    }
}
