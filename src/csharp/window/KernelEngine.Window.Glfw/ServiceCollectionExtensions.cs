using System.Runtime.InteropServices;
using KernelEngine.Configuration;
using KernelEngine.Window.Glfw.Native;
using KernelEngine.Common.Native;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Input;
using KernelEngine.Logger;

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
            var width      = (int)cfg.GetInt("runtime.window", "width", 1280);
            var height     = (int)cfg.GetInt("runtime.window", "height", 720);
            var title      = cfg.GetString("runtime.window", "title", "KernelEngine");
            var fullscreen = cfg.GetBool("runtime.window", "fullscreen", false);
            return CreateWindow(sp, width, height, title, fullscreen);
        });
        return services;
    }

    /// <summary>
    /// Backward-compatible overload that passes window settings inline, bypassing the
    /// Project file. Lets examples that have not migrated to Project keep working.
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
            var logger = sp.GetService<INativeLogger>();
            var input  = sp.GetService<INativeInput>();

            var @params = new ke_window_glfw_params
            {
                logger = logger != null ? logger.Native : null,
                input      = input  != null ? input.Native  : null,
                title      = (sbyte*)titlePtr,
                width      = width,
                height     = height,
                fullscreen = fullscreen,
            };

            ke_error* err = null;
            var handle = KernelEngine.Window.Glfw.Native.NativeMethods.window_glfw_create(&@params, &err);
            if (handle.@ref == null) throw KernelError.FromNative(err, "window_glfw_create");
            return new KernelEngine.Window.Window(handle);
        }
        finally
        {
            Marshal.FreeHGlobal(titlePtr);
        }
    }
}
