using System.Runtime.InteropServices;

using KernelEngine.Configuration;
using KernelEngine.Input;
using KernelEngine.Logger;
using KernelEngine.Window.Glfw.Native;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Window.Glfw;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a GLFW-backed <see cref="KernelEngine.Window.Window"/> singleton. Reads
    /// <c>[runtime.window] width/height/title/fullscreen</c> from the Project file when
    /// present; otherwise defaults to 1280x720 windowed, titled "KernelEngine".
    /// </summary>
    public static IServiceCollection AddGlfwWindow(this IServiceCollection services)
    {
        services.TryAddConfigurationSingleton();
        services.AddSingleton<IWindow>(sp =>
        {
            var cfg = sp.GetRequiredService<IConfiguration>();
            var width = (int)cfg.GetInt("runtime.window", "width", 1280);
            var height = (int)cfg.GetInt("runtime.window", "height", 720);
            var title = cfg.GetString("runtime.window", "title", "KernelEngine");
            var fullscreen = cfg.GetBool("runtime.window", "fullscreen", false);
            return CreateWindow(sp, width, height, title, fullscreen);
        });
        return services;
    }

    /// <summary>
    /// Registers the window singleton with the given settings, windowed, bypassing the Project
    /// file.
    /// </summary>
    public static IServiceCollection AddGlfwWindow(
        this IServiceCollection services, int width, int height, string title)
    {
        services.AddSingleton<IWindow>(sp => CreateWindow(sp, width, height, title, fullscreen: false));
        return services;
    }

    private static unsafe IWindow CreateWindow(
        IServiceProvider sp, int width, int height, string title, bool fullscreen)
    {
        var titlePtr = Marshal.StringToHGlobalAnsi(title);
        try
        {
            if (sp.GetService<ILogger>() is { } logger)
                KernelEngine.Window.Glfw.Native.NativeMethods.window_glfw_set_log_callback(LogCallbackNative.Pointer, LogCallbackNative.Pin(logger.Log));
            var input = sp.GetService<INativeInput>();

            var @params = new ke_window_glfw_params
            {
                input = input != null ? input.Native : null,
                title = (sbyte*)titlePtr,
                width = width,
                height = height,
                fullscreen = fullscreen,
            };

            KernelEngine.Window.Native.ke_window_handle handle;
            KernelEngine.NativeResults.ThrowIfFailed(
                KernelEngine.Window.Glfw.Native.NativeMethods.window_glfw_create(&@params, &handle), "ke_window_glfw_create");
            return new KernelEngine.Window.Window(handle);
        }
        finally
        {
            Marshal.FreeHGlobal(titlePtr);
        }
    }
}
