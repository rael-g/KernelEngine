using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
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
                    allocator = sp.GetRequiredService<Allocator>().Native,
                    logger    = logger != null ? logger.Native : null,
                };
                ke_image_loader_handle handle;
                KernelException.ThrowIfFailed(Native.NativeMethods.image_loader_stb_create(&@params, &handle, null).ToManaged());
                return new ImageLoader(handle);
            }
        });
        return services;
    }
}
