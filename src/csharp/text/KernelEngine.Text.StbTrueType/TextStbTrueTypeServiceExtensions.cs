using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Text.StbTrueType.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Text.StbTrueType;

public static class TextStbTrueTypeServiceExtensions
{
    /// <summary>
    /// Registers a stb_truetype-backed <see cref="IFontLoader"/> singleton. Fonts loaded through
    /// <c>Assets.LoadFontAsync(path, pixelSize)</c> route here for CPU decode + atlas bake; the
    /// resulting atlas texture is uploaded via the existing <c>ResourceManager.CreateTextureAsync</c>
    /// pipeline. Requires <c>AddKernel()</c> first.
    /// </summary>
    public static IServiceCollection AddTextStbTrueType(this IServiceCollection services)
    {
        services.AddSingleton<IFontLoader>(sp =>
        {
            unsafe
            {
                var logger = sp.GetService<INativeLogger>();
                var @params = new ke_font_loader_stb_params
                {
                    allocator = sp.GetRequiredService<Allocator>().Native,
                    logger    = logger != null ? logger.Native : null,
                };
                ke_font_loader_handle handle;
                KernelException.ThrowIfFailed(
                    KernelEngine.Text.StbTrueType.Native.NativeMethods.font_loader_stb_create(&@params, &handle, null).ToManaged());
                return new FontLoader(handle);
            }
        });
        return services;
    }
}
