using System.Diagnostics;

using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace KernelEngine;

/// <summary>
/// A running engine, made by a container from the contracts of its parts: the standard schedules made by the
/// registered schedule factory and added to the scheduler, every registered module attached to them in the order
/// it was registered, every engine part made, and the engine's node types registered. It ticks until the window
/// closes or a node asks to exit. Disposing it detaches the modules and releases the schedules; the container
/// releases the parts.
/// </summary>
public sealed class Engine : IDisposable
{
    readonly Module.Module[] _modules;
    bool _disposed;

    internal Engine(IServiceProvider services)
    {
        Configuration = services.GetRequiredService<Configuration.Configuration>();
        Window = services.GetRequiredService<Window.Window>();
        Scheduler = services.GetRequiredService<Scheduler.Scheduler>();
        Runtime = services.GetRequiredService<Runtime.Runtime>();
        var make = services.GetRequiredService<Func<Schedule.Schedule>>();
        Schedules = new EngineSchedules { Startup = make(), PreUpdate = make(), Fixed = make(), Update = make(), Shutdown = make() };
        Sets = EngineSets.Register(Schedules);
        Schedules.AddTo(Scheduler);
        foreach (var _ in services.GetServices<IEnginePart>()) { }
        _modules = [.. services.GetServices<Module.Module>()];
        foreach (var module in _modules) Schedules.Attach(module, Sets);
        Types = services.GetRequiredService<NodeTypes>();
        Scenes = services.GetRequiredService<SceneFiles>();
        Types.RegisterEngineNodeTypes();
        Nodes = new NodeWorld(Types, services.GetService<ILoggerFactory>());
    }

    /// <summary>The project file's values.</summary>
    public Configuration.Configuration Configuration { get; }

    /// <summary>The window.</summary>
    public Window.Window Window { get; }

    /// <summary>The frame loop that ticks the standard schedules.</summary>
    public Scheduler.Scheduler Scheduler { get; }

    /// <summary>The phase loop.</summary>
    public Runtime.Runtime Runtime { get; }

    /// <summary>The standard schedules <see cref="Scheduler"/> runs.</summary>
    public EngineSchedules Schedules { get; }

    /// <summary>The standard sets, each in one of <see cref="Schedules"/>.</summary>
    public EngineSets Sets { get; }

    /// <summary>The node types, with the engine's own registered.</summary>
    public NodeTypes Types { get; }

    /// <summary>The scene files.</summary>
    public SceneFiles Scenes { get; }

    /// <summary>The node types as C# registers them.</summary>
    public NodeWorld Nodes { get; }

    /// <summary>
    /// Opens the scene file at <paramref name="firstScene"/> (a <c>res://</c> path, as <c>Scenes</c> names
    /// them), or the scene of the project's scenes directory the project file's
    /// <c>project.default_scene</c> names, and ticks until the window closes or a node exits.
    /// </summary>
    public void Run(string? firstScene = null)
    {
        var slot = new SceneSlotComponent();
        slot.Path = firstScene ?? $"res://scenes/{Configuration.GetString("project", "default_scene", "Main")}.scene.toml";
        Types.Spawn(Schedules.PreUpdate.Commands(), Nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(Nodes.Component("scene_slot"), slot)]);

        var clock = Stopwatch.StartNew();
        var previous = clock.Elapsed.TotalSeconds;
        while (!Window.ShouldClose() && !Runtime.ExitRequested() && !Scheduler.ExitRequested())
        {
            Window.PollEvents();
            var current = clock.Elapsed.TotalSeconds;
            Scheduler.Tick((float)(current - previous));
            Runtime.Tick((float)(current - previous));
            previous = current;
        }
        Runtime.Flush();
    }

    /// <summary>Shuts the loop down, detaches every module, the last attached first, and releases the schedules.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Runtime.Flush();
        Runtime.UnloadModules();
        Scheduler.Shutdown();
        for (var i = _modules.Length - 1; i >= 0; i--) _modules[i].Detach();
        Schedules.Shutdown.Dispose();
        Schedules.Update.Dispose();
        Schedules.Fixed.Dispose();
        Schedules.PreUpdate.Dispose();
        Schedules.Startup.Dispose();
    }
}
