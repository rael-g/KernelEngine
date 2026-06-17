using System.Runtime.InteropServices;
using KernelEngine.Configuration;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx.Native;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace KernelEngine.Render.Bgfx;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a bgfx-backed <see cref="KernelEngine.Kernel.Renderer"/> singleton.
    /// Reads <c>[runtime.renderer]</c> from Project.toml when present; otherwise uses
    /// <see cref="BgfxRendererOptions"/> defaults. Requires <c>AddKernel()</c> and a
    /// registered <see cref="KernelEngine.Kernel.Window"/> to be called first.
    /// </summary>
    public static IServiceCollection AddBgfxRenderer(this IServiceCollection services)
    {
        services.AddProjectConfigSection<BgfxRendererOptions>("runtime.renderer");
        services.AddSingleton<IRenderer>(sp =>
        {
            var opts = sp.GetRequiredService<IOptions<BgfxRendererOptions>>().Value;
            return CreateRenderer(sp, opts);
        });
        return services;
    }

    /// <summary>
    /// Backward-compatible overload that passes the shader path (and optional vsync) inline.
    /// Equivalent to <c>AddBgfxRenderer()</c> + <c>Configure&lt;BgfxRendererOptions&gt;(...)</c>;
    /// lets examples that have not migrated to Project.toml keep working.
    /// </summary>
    public static IServiceCollection AddBgfxRenderer(
        this IServiceCollection services, string shaderPath, bool vsync = true)
    {
        services.AddBgfxRenderer();
        services.Configure<BgfxRendererOptions>(o =>
        {
            o.ShaderPath = shaderPath;
            o.Vsync = vsync;
        });
        return services;
    }

    private static unsafe IRenderer CreateRenderer(IServiceProvider sp, BgfxRendererOptions opts)
    {
        var shaderPath = ResolveShaderPath(opts.ShaderPath);
        var shaderPtr = Marshal.StringToHGlobalAnsi(shaderPath);
        try
        {
            var logger = sp.GetService<INativeLogger>();

            var @params = new ke_render_bgfx_params
            {
                allocator     = sp.GetRequiredService<Allocator>().Native,
                logger        = logger != null ? logger.Native : null,
                window        = ((Window)sp.GetRequiredService<IWindow>()).Native,
                shader_path   = (sbyte*)shaderPtr,
                vsync         = opts.Vsync,
                renderer_type = (uint)opts.Backend,
            };

            ke_render* native;
            KernelException.ThrowIfFailed(
                KernelEngine.Render.Bgfx.Native.NativeMethods.render_bgfx_create(&@params, &native, null).ToManaged());
            return new KernelEngine.Kernel.Renderer(native);
        }
        finally
        {
            Marshal.FreeHGlobal(shaderPtr);
        }
    }

    private static string ResolveShaderPath(string configured) =>
        Path.IsPathRooted(configured) ? configured : Path.Combine(AppContext.BaseDirectory, configured);
}
