
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Runtime;

namespace KernelEngine.Window.Glfw;

/// <summary>
/// GLFW window as an <see cref="IRuntimeModule"/>. Registers <see cref="IWindow"/>
/// during Configure and adds the PollEvents system to PreUpdate during OnLoad.
/// The runtime never knows what GLFW is — it sees an opaque module.
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

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        // PreUpdate is the canonical phase for OS event pump: by the time any
        // Update / FixedUpdate system runs, input + close events are already
        // consumed. The window reference is captured into the system closure
        // so the runtime callback doesn't need to know about the container.
        var window = services.GetRequiredService<IWindow>();
        runtime.RegisterSystem("Glfw.PollEvents", RuntimePhase.PreUpdate, (_, _) =>
        {
            window.PollEvents();
        });
    }
}
