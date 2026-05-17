using System.Runtime.InteropServices;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx.Native;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Bgfx;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a bgfx-backed <see cref="KernelEngine.Kernel.Renderer"/> singleton.
    /// Requires <c>AddKernel()</c> and a registered <see cref="KernelEngine.Kernel.Window"/> to be called first.
    /// </summary>
    public static IServiceCollection AddBgfxRenderer(
        this IServiceCollection services,
        string shaderPath,
        bool vsync = true)
    {
        services.AddSingleton<IRenderer>(sp =>
        {
            var shaderPtr = Marshal.StringToHGlobalAnsi(shaderPath);
            try
            {
                unsafe
                {
                    var logger = sp.GetService<Logger>();

                    var @params = new ke_render_bgfx_params
                    {
                        allocator = sp.GetRequiredService<Allocator>().Native,
                        logger = logger != null ? logger.Native : null,
                        window = sp.GetRequiredService<IWindow>().Native,
                        shader_path = (sbyte*)shaderPtr,
                        vsync = (byte)(vsync ? 1 : 0),
                    };

                    ke_render* native;
                    KernelException.ThrowIfFailed(
                        KernelEngine.Render.Bgfx.Native.NativeMethods.render_bgfx_create(&@params, &native));
                    return new KernelEngine.Kernel.Renderer(native);
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
