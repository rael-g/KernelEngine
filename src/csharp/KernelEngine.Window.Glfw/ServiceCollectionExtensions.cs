using System.Runtime.InteropServices;
using KernelEngine.Kernel;
using KernelEngine.Window.Glfw.Native;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Window.Glfw;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a GLFW-backed <see cref="KernelEngine.Kernel.Window"/> singleton.
    /// Requires <c>AddKernel()</c> to be called first.
    /// </summary>
    public static IServiceCollection AddGlfwWindow(
        this IServiceCollection services,
        int width, int height, string title)
    {
        services.AddSingleton<KernelEngine.Kernel.Window>(sp =>
        {
            var titlePtr = Marshal.StringToHGlobalAnsi(title);
            try
            {
                unsafe
                {
                    var logger = sp.GetService<Logger>();

                    var @params = new ke_window_glfw_params
                    {
                        allocator = sp.GetRequiredService<Allocator>().Native,
                        logger = logger != null ? logger.Native : null,
                        title = (sbyte*)titlePtr,
                        width = width,
                        height = height,
                        fullscreen = 0,
                    };

                    ke_window* native;
                    KernelException.ThrowIfFailed(
                        KernelEngine.Window.Glfw.Native.NativeMethods.window_glfw_create(&@params, &native));
                    return new KernelEngine.Kernel.Window(native);
                }
            }
            finally
            {
                Marshal.FreeHGlobal(titlePtr);
            }
        });

        return services;
    }
}
