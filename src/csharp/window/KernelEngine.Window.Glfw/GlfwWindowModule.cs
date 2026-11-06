using KernelEngine.Runtime;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Window.Glfw;

/// <summary>
/// GLFW window as an <see cref="IRuntimeModule"/>. Registers <see cref="IWindow"/> during
/// Configure, created with the registered <see cref="GlfwWindowConfig"/>, or the defaults when
/// none is registered. The host polls events: it calls <see cref="IWindow.PollEvents"/> on the
/// window's thread before each <c>Tick</c>.
/// </summary>
public sealed class GlfwWindowModule : IRuntimeModule
{
    /// <inheritdoc/>
    public string Name => "Glfw.Window";

    /// <inheritdoc/>
    public void Configure(IServiceCollection services) => services.AddGlfwWindow();

    /// <inheritdoc/>
    public void OnLoad(IRuntime runtime, IServiceProvider services) { }
}
