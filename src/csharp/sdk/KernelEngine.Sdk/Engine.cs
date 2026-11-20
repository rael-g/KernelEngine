using System.Diagnostics;

using KernelEngine.EngineNodes;
using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace KernelEngine;

/// <summary>
/// A running engine, made by a container from the contracts of its parts: the standard schedules made by the
/// registered schedule factory and added to the scheduler, every registered module that takes the schedules and their
/// sets created on them, in the order it was registered, and the engine's node types registered. Running it waits
/// until every registered <see cref="EngineReadiness"/> finished, attaches every registered <see cref="Module.Module"/>
/// to the schedules in the order it was registered, and ticks until the window closes or a node asks to exit.
/// Disposing it detaches the attached modules, releases the created ones, the last first, and releases the schedules;
/// the container releases the parts.
/// </summary>
public sealed class Engine : IDisposable
{
    readonly Module.Module[] _modules;
    readonly List<IDisposable> _hooked = [];
    readonly List<EngineReadiness> _pending;
    bool _attached;
    bool _disposed;

    internal Engine(IServiceProvider services)
    {
        Configuration = services.GetRequiredService<Configuration.Configuration>();
        Window = services.GetRequiredService<Window.Window>();
        Scheduler = services.GetRequiredService<Scheduler.Scheduler>();
        var make = services.GetRequiredService<Func<Schedule.Schedule>>();
        Schedules = new EngineSchedules { Startup = make(), PreUpdate = make(), Fixed = make(), Update = make(), Shutdown = make(), Render = services.GetKeyedService<Schedule.Schedule>("render") };
        Sets = EngineSets.Register(Schedules);
        Schedules.AddTo(Scheduler);
        if (services.GetService<Extraction.Extraction>() is { } extraction && Schedules.Render is { } render) EngineSchedules.AddRender(Scheduler, extraction, render);
        foreach (var create in services.GetServices<Func<EngineSchedules, EngineSets, IDisposable>>()) _hooked.Add(create(Schedules, Sets));
        _modules = [.. services.GetServices<Module.Module>()];
        _pending = [.. services.GetServices<EngineReadiness>()];
        Types = services.GetRequiredService<NodeTypes>();
        Scenes = services.GetRequiredService<Func<EngineSchedules, EngineSets, SceneFiles>>()(Schedules, Sets);
        _hooked.Add(Scenes);
        Types.RegisterEngineNodeTypes();
        Nodes = new NodeWorld(Types, services.GetService<ILoggerFactory>());
    }

    /// <summary>The project file's values.</summary>
    public Configuration.Configuration Configuration { get; }

    /// <summary>The window.</summary>
    public Window.Window Window { get; }

    /// <summary>The frame loop that ticks the standard schedules.</summary>
    public Scheduler.Scheduler Scheduler { get; }

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
    /// Waits, pumping the window's events, until every part is ready; attaches the modules; opens the scene file at
    /// <paramref name="firstScene"/> (a <c>res://</c> path, as <c>Scenes</c> names them), or the scene of the
    /// project's scenes directory the project file's <c>project.default_scene</c> names; and ticks until the window
    /// closes or a node exits.
    /// </summary>
    /// <exception cref="Exception">A part finished getting ready with a failure.</exception>
    public void Run(string? firstScene = null)
    {
        while (_pending.Count > 0 && !Window.ShouldClose())
        {
            Window.PollEvents();
            _pending.RemoveAll(part => part.Ready());
        }
        if (!_attached)
        {
            foreach (var module in _modules) Schedules.Attach(module, Sets);
            _attached = true;
        }
        var slot = new SceneSlotComponent();
        slot.Path = firstScene ?? $"res://scenes/{Configuration.GetString("project", "default_scene", "Main")}.scene.toml";
        Types.Spawn(Schedules.PreUpdate.Commands(), Nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(Nodes.Component("scene_slot"), slot)]);

        var clock = Stopwatch.StartNew();
        var previous = clock.Elapsed.TotalSeconds;
        while (!Window.ShouldClose() && !Scheduler.ExitRequested())
        {
            Window.PollEvents();
            var current = clock.Elapsed.TotalSeconds;
            Scheduler.Tick((float)(current - previous));
            previous = current;
        }
    }

    /// <summary>Shuts the loop down, detaches every attached module, the last attached first, releases every created
    /// module, the last created first, and releases the schedules.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Scheduler.Shutdown();
        if (_attached)
            for (var i = _modules.Length - 1; i >= 0; i--) _modules[i].Detach();
        for (var i = _hooked.Count - 1; i >= 0; i--) _hooked[i].Dispose();
        Schedules.Shutdown.Dispose();
        Schedules.Update.Dispose();
        Schedules.Fixed.Dispose();
        Schedules.PreUpdate.Dispose();
        Schedules.Startup.Dispose();
    }
}
