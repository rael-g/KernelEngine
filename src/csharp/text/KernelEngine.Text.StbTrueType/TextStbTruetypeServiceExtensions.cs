
using KernelEngine.Common.Native;
using KernelEngine.Text.Native;
using KernelEngine.Text.StbTrueType.Native;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Logger;

namespace KernelEngine.Text.StbTrueType;

public static class TextStbTrueTypeServiceExtensions
{
    /// <summary>
    /// Registers a stb_truetype-backed <see cref="IFontLoader"/> singleton. Fonts loaded through
    /// <c>Assets.LoadFontAsync(path, pixelSize)</c> route here for CPU decode + atlas bake; the
    /// resulting atlas texture is uploaded via the existing <c>ResourceManager.CreateTextureAsync</c>
    /// pipeline.
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
                    logger = logger != null ? logger.Native : null,
                };
                ke_error* err = null;
                var handle = KernelEngine.Text.StbTrueType.Native.NativeMethods.font_loader_stb_create(&@params, &err);
                if (handle.@ref == null) throw KernelError.FromNative(err, "font_loader_stb_create");
                return new FontLoader(handle);
            }
        });
        return services;
    }
}
