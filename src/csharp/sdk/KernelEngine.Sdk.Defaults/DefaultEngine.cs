using KernelEngine.Framework.Nodes;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine;

/// <summary>An engine of every default part, with the container it was made in, which disposing it releases.</summary>
public sealed class DefaultEngine : IDisposable
{
    readonly ServiceProvider _services;

    DefaultEngine(ServiceProvider services)
    {
        _services = services;
        Engine = services.GetRequiredService<Engine>();
    }

    /// <summary>Makes an engine of every default part, configured by the project file in <paramref name="projectDir"/>.</summary>
    /// <param name="projectDir">The directory holding the project file, its scenes and its assets.</param>
    public static DefaultEngine Create(string projectDir) =>
        new(new ServiceCollection().AddDefaultCore(projectDir).AddKernelEngine().BuildServiceProvider());

    /// <summary>The engine.</summary>
    public Engine Engine { get; }

    /// <summary>The node types as C# registers them.</summary>
    public NodeWorld Nodes => Engine.Nodes;

    /// <summary>Opens the first scene and ticks until the window closes or a node exits; see <see cref="Engine.Run"/>.</summary>
    /// <param name="firstScene">A <c>res://</c> path; null takes the project's default scene.</param>
    public void Run(string? firstScene = null) => Engine.Run(firstScene);

    /// <summary>Releases the engine and every part, the last made first.</summary>
    public void Dispose() => _services.Dispose();
}
