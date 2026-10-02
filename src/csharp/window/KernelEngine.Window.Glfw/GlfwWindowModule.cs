
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Runtime;

namespace KernelEngine.Window.Glfw;

/// <summary>
/// GLFW window as an <see cref="IRuntimeModule"/>. Registers <see cref="IWindow"/>
/// during Configure. The host polls events: it calls <see cref="IWindow.PollEvents"/> on
/// the window's thread before each <c>Tick</c>.
/// </summary>
public sealed class GlfwWindowModule : IRuntimeModule
{
    private readonly int?    _width;
    private readonly int?    _height;
    private readonly string? _title;

    public string Name => "Glfw.Window";

    /// <summary>
    /// Reads window settings from the Project file's <c>[runtime.window]</c>
    /// section (width / height / title / fullscreen), falling back to
    /// compile-time defaults if the section / file is absent.
    /// </summary>
    public GlfwWindowModule() { }

    /// <summary>
    /// Inline overrides, bypassing the Project file. Useful for examples that
    /// don't ship one.
    /// </summary>
    public GlfwWindowModule(int width, int height, string title)
    {
        _width  = width;
        _height = height;
        _title  = title;
    }

    public void Configure(IServiceCollection services)
    {
        if (_width is { } w && _height is { } h && _title is { } t)
            services.AddGlfwWindow(w, h, t);
        else
            services.AddGlfwWindow();
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services) { }
}
