using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Bgfx;

/// <summary>
/// bgfx renderer as an <see cref="IRuntimeModule"/>. Registers
/// <see cref="IRenderer"/> during Configure; during OnLoad initializes the
/// renderer and adds a system to <see cref="RuntimePhase.Extract"/> that calls
/// <c>Frame()</c> once per tick. The runtime never knows what bgfx is — it sees
/// an opaque module that talks to a renderer via the contract.
/// </summary>
/// <remarks>
/// Depends on an <see cref="IWindow"/> being registered (e.g. via
/// <c>GlfwWindowModule</c> or any other window plugin). Resolution happens
/// inside the renderer factory; if no IWindow is registered, OnLoad surfaces
/// a clear error from <c>GetRequiredService</c>.
/// </remarks>
public sealed class BgfxRenderModule : IRuntimeModule
{
    private readonly string                _shaderPath;
    private readonly bool                  _vsync;
    private readonly (float r, float g, float b, float a)? _clearColor;

    public string Name => "Bgfx.Render";

    /// <param name="shaderPath">Directory containing compiled shader binaries (relative or absolute).</param>
    /// <param name="vsync">When true, swap is synchronized to display refresh.</param>
    /// <param name="clearColor">Optional clear color applied every Update tick. Null keeps the previous framebuffer contents.</param>
    public BgfxRenderModule(string shaderPath, bool vsync = true,
                            (float r, float g, float b, float a)? clearColor = null)
    {
        _shaderPath = shaderPath;
        _vsync      = vsync;
        _clearColor = clearColor;
    }

    public void Configure(IServiceCollection services)
    {
        services.AddBgfxRenderer(_shaderPath, _vsync);
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var renderer = services.GetRequiredService<IRenderer>();
        renderer.Initialize();

        if (_clearColor is { } c)
        {
            runtime.RegisterSystem("Bgfx.ClearColor", RuntimePhase.Update, (_, _) =>
            {
                renderer.ClearColor(c.r, c.g, c.b, c.a);
            });
        }

        runtime.RegisterSystem("Bgfx.Frame", RuntimePhase.Extract, (_, _) =>
        {
            renderer.Frame();
        });
    }
}
