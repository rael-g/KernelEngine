using KernelEngine.Logger;

using KernelEngine.Common.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Asset.StbImage;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers an stb_image-backed <see cref="IImageLoader"/> singleton. Requires
    /// <c>AddKernel()</c> first.
    /// </summary>
    public static IServiceCollection AddStbImageLoader(this IServiceCollection services)
    {
        services.AddSingleton<IImageLoader>(sp =>
        {
            unsafe
            {
                var logger = sp.GetService<INativeLogger>();
                var @params = new Native.ke_image_loader_stb_params
                {
                    logger = logger != null ? logger.Native : null,
                };
                ke_error* err = null;
                var handle = Native.NativeMethods.image_loader_stb_create(&@params, &err);
                if (handle.@ref == null) throw KernelError.FromNative(err, "image_loader_stb_create");
                return new ImageLoader(handle);
            }
        });
        return services;
    }
}
