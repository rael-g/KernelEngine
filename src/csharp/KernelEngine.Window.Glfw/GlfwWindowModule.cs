using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Window.Glfw;

/// <summary>
/// GLFW window as an <see cref="IRuntimeModule"/>. Registers <see cref="IWindow"/>
/// during Configure and adds the PollEvents system to PreUpdate during OnLoad.
/// The runtime never knows what GLFW is — it sees an opaque module.
/// </summary>
public sealed class GlfwWindowModule : IRuntimeModule
{
    private readonly int    _width;
    private readonly int    _height;
    private readonly string _title;

    public string Name => "Glfw.Window";

    public GlfwWindowModule(int width, int height, string title)
    {
        _width  = width;
        _height = height;
        _title  = title;
    }

    public void Configure(IServiceCollection services)
    {
        // Reuse the existing extension — keeps the GLFW init logic centralized.
        services.AddGlfwWindow(_width, _height, _title);
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
