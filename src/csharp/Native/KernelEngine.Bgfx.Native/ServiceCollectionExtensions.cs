using System.Runtime.InteropServices;
using KernelEngine;
using KernelEngine.Bgfx.Native;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Bgfx;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a bgfx-backed <see cref="Renderer"/> singleton.
    /// Requires <c>AddKernel()</c> and a registered <see cref="Window"/> to be called first.
    /// </summary>
    public static IServiceCollection AddBgfxRenderer(
        this IServiceCollection services,
        string shaderPath)
    {
        services.AddSingleton<Renderer>(sp =>
        {
            var shaderPtr = Marshal.StringToHGlobalAnsi(shaderPath);
            try
            {
                unsafe
                {
                    var logger = sp.GetService<Logger>();
                    var pipe = sp.GetService<MessagePipe>();

                    var @params = new ke_render_bgfx_params
                    {
                        allocator = sp.GetRequiredService<Allocator>().Native,
                        logger = logger != null ? logger.Native : null,
                        message_pipe = pipe != null ? pipe.Native : null,
                        window = sp.GetRequiredService<Window>().Native,
                        shader_path = (sbyte*)shaderPtr,
                    };

                    ke_render* native;
                    KernelException.ThrowIfFailed(
                        KernelEngine.Bgfx.Native.NativeMethods.render_bgfx_create(&@params, &native));
                    return new Renderer(native);
                }
            }
            finally
            {
                Marshal.FreeHGlobal(shaderPtr);
            }
        });

        return services;
    }
}
