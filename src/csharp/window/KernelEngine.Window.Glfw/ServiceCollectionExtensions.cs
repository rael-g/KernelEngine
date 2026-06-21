using System.Runtime.InteropServices;
using KernelEngine.Configuration;
using KernelEngine.Window.Glfw.Native;
using KernelEngine.Common.Native;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using KernelEngine.Input;
using KernelEngine.Logger;

namespace KernelEngine.Window.Glfw;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a GLFW-backed <see cref="KernelEngine.Window.Window"/> singleton.
    /// Reads <c>[runtime.window]</c> from Project.toml when present; otherwise uses
    /// <see cref="WindowOptions"/> defaults. Requires <c>AddKernel()</c> to be called first.
    /// </summary>
    public static IServiceCollection AddGlfwWindow(this IServiceCollection services)
    {
        services.AddProjectConfigSection<WindowOptions>("runtime.window");
        services.AddSingleton<IWindow>(sp =>
        {
            var opts = sp.GetRequiredService<IOptions<WindowOptions>>().Value;
            return CreateWindow(sp, opts);
        });
        return services;
    }

    /// <summary>
    /// Backward-compatible overload that passes window settings inline. Equivalent to
    /// <c>AddGlfwWindow()</c> + <c>Configure&lt;WindowOptions&gt;(o =&gt; ...)</c>; lets
    /// examples that have not migrated to Project.toml keep working.
    /// </summary>
    public static IServiceCollection AddGlfwWindow(
        this IServiceCollection services, int width, int height, string title)
    {
        services.AddGlfwWindow();
        services.Configure<WindowOptions>(o =>
        {
            o.Width = width;
            o.Height = height;
            o.Title = title;
        });
        return services;
    }

    private static unsafe IWindow CreateWindow(IServiceProvider sp, WindowOptions opts)
    {
        var titlePtr = Marshal.StringToHGlobalAnsi(opts.Title);
        try
        {
            var logger = sp.GetService<INativeLogger>();
            var input  = sp.GetService<INativeInput>();

            var @params = new ke_window_glfw_params
            {
                logger = logger != null ? logger.Native : null,
                input      = input  != null ? input.Native  : null,
                title      = (sbyte*)titlePtr,
                width      = opts.Width,
                height     = opts.Height,
                fullscreen = opts.Fullscreen,
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
