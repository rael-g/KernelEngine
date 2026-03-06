using System.Runtime.InteropServices;
using KernelEngine;
using KernelEngine.Glfw.Native;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Glfw;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a GLFW-backed <see cref="Window"/> singleton.
    /// Requires <c>AddKernel()</c> to be called first.
    /// </summary>
    public static IServiceCollection AddGlfwWindow(
        this IServiceCollection services,
        int width, int height, string title)
    {
        services.AddSingleton<Window>(sp =>
        {
            var titlePtr = Marshal.StringToHGlobalAnsi(title);
            try
            {
                unsafe
                {
                    var logger = sp.GetService<Logger>();
                    var pipe = sp.GetService<MessagePipe>();

                    var @params = new ke_window_glfw_params
                    {
                        allocator = sp.GetRequiredService<Allocator>().Native,
                        logger = logger != null ? logger.Native : null,
                        message_pipe = pipe != null ? pipe.Native : null,
                        width = width,
                        height = height,
                        title = (sbyte*)titlePtr,
                    };

                    ke_window* native;
                    KernelException.ThrowIfFailed(
                        KernelEngine.Glfw.Native.NativeMethods.window_glfw_create(&@params, &native));
                    return new Window(native);
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
