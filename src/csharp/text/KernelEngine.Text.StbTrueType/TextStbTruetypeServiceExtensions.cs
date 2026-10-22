
using KernelEngine.Common.Native;
using KernelEngine.Logger;
using KernelEngine.Text.Native;
using KernelEngine.Text.StbTrueType.Native;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Text.StbTrueType;

public static class TextStbTrueTypeServiceExtensions
{
    /// <summary>
    /// Registers a stb_truetype-backed <see cref="IFontLoader"/> singleton, and the same
    /// loader as <see cref="INativeFontLoader"/>. The library logs to the registered
    /// <see cref="ILogger"/>, or to stderr when there is none.
    /// </summary>
    public static IServiceCollection AddTextStbTrueType(this IServiceCollection services)
    {
        services.AddSingleton<IFontLoader>(sp =>
        {
            unsafe
            {
                if (sp.GetService<ILogger>() is { } logger)
                    KernelEngine.Text.StbTrueType.Native.NativeMethods.text_stb_truetype_set_log_callback(LogCallbackNative.Pointer, LogCallbackNative.Pin(logger.Log));
                ke_error* err = null;
                var handle = KernelEngine.Text.StbTrueType.Native.NativeMethods.font_loader_stb_create(&err);
                if (handle.@ref == null) throw NativeErrors.FromNative(err, "font_loader_stb_create");
                return new FontLoader(handle);
            }
        });
        services.AddSingleton<INativeFontLoader>(sp => (FontLoader)sp.GetRequiredService<IFontLoader>());
        return services;
    }
}
