using System.Diagnostics;
using System.Numerics;

using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.View;
using KernelEngine.Window.Glfw;

namespace KernelEngine;

/// <summary>
/// The parts an engine is composed of, in the order they are made; a replacement given to
/// <see cref="EngineBuilder"/> receives the ones made before it.
/// </summary>
public sealed class EngineParts
{
    /// <summary>The directory holding the project file, its scenes and its assets.</summary>
    public required string ProjectDir { get; init; }

    /// <summary>The worker pool.</summary>
    public required EnkiTaskPool Pool { get; init; }

    /// <summary>What every file is read through.</summary>
    public required PoolIo Io { get; init; }

    /// <summary>The project file's values.</summary>
    public required DefaultConfiguration Configuration { get; init; }

    /// <summary>The input the window feeds.</summary>
    public required Input.Input Input { get; init; }

    /// <summary>The window.</summary>
    public required GlfwWindow Window { get; init; }

    /// <summary>The world's entities and components.</summary>
    public required FlecsEcsRegistry Ecs { get; init; }

    /// <summary>The phase loop.</summary>
    public required DefaultRuntime Runtime { get; init; }

    /// <summary>The GPU device.</summary>
    public required WebgpuGpuDevice Gpu { get; init; }

    /// <summary>The asset resolver, holding the project root.</summary>
    public required DefaultAssetResolver Assets { get; init; }

    /// <summary>The scene tree.</summary>
    public required DefaultSceneTree Tree { get; init; }

    /// <summary>The render service the passes record into.</summary>
    public required DefaultRenderService Service { get; init; }

    /// <summary>The handedness of view space.</summary>
    public required RhViewSpace ViewSpace { get; init; }

    /// <summary>The camera the passes read.</summary>
    public required DefaultRenderCamera Camera { get; init; }

    /// <summary>The scene the passes draw.</summary>
    public required DefaultRenderSceneResolve Scene { get; init; }

    /// <summary>The frame the passes run in.</summary>
    public required DefaultRenderFrame Frame { get; init; }

    /// <summary>The font a label falls back to.</summary>
    public required string DefaultFont { get; init; }
}

/// <summary>
/// A running engine: every part made, the engine's node types registered, and the loop that ticks it
/// until the window closes or a node asks to exit. Disposing it releases the parts in the reverse of
/// the order they were made.
/// </summary>
public sealed class Engine : IDisposable
{
    readonly List<IDisposable> _owned;

    internal Engine(EngineParts parts, List<IDisposable> owned, DefaultNodeTypes types)
    {
        Parts = parts;
        _owned = owned;
        Types = types;
        Nodes = new NodeWorld(types);
    }

    /// <summary>Makes an engine of every default part, configured by the project file in <paramref name="projectDir"/>.</summary>
    public static Engine Create(string projectDir) => Builder(projectDir).Build();

    /// <summary>A builder of an engine whose parts can be replaced one by one.</summary>
    public static EngineBuilder Builder(string projectDir) => new(projectDir);

    /// <summary>The parts the engine is made of.</summary>
    public EngineParts Parts { get; }

    /// <summary>The node types, with the engine's own registered.</summary>
    public DefaultNodeTypes Types { get; }

    /// <summary>The node types as C# registers them.</summary>
    public NodeWorld Nodes { get; }

    /// <summary>
    /// Opens the scene <paramref name="firstScene"/> of the project's scenes directory, or the
    /// project file's <c>project.default_scene</c>, and ticks until the window closes or a node exits.
    /// </summary>
    public void Run(string? firstScene = null)
    {
        var scene = firstScene ?? Parts.Configuration.GetString("project", "default_scene", "Main");
        var slot = new SceneSlotComponent();
        slot.PathText = $"res://scenes/{scene}.scene.toml";
        Types.Spawn(Parts.Runtime.Commands(), Nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(Nodes.Component("scene_slot"), slot)]);

        var clock = Stopwatch.StartNew();
        var previous = clock.Elapsed.TotalSeconds;
        while (!Parts.Window.ShouldClose() && !Parts.Runtime.ExitRequested())
        {
            Parts.Window.PollEvents();
            var current = clock.Elapsed.TotalSeconds;
            Parts.Runtime.Tick((float)(current - previous));
            previous = current;
        }
        Parts.Runtime.Flush();
    }

    /// <summary>Releases every part, the last made first.</summary>
    public void Dispose()
    {
        Parts.Runtime.Flush();
        Parts.Runtime.UnloadModules();
        for (var i = _owned.Count - 1; i >= 0; i--) _owned[i].Dispose();
        _owned.Clear();
    }

    internal static Vector4 ClearColor(DefaultConfiguration config) => new(
        (float)config.GetDouble("render", "clear_color.0", 0.0),
        (float)config.GetDouble("render", "clear_color.1", 0.0),
        (float)config.GetDouble("render", "clear_color.2", 0.0),
        (float)config.GetDouble("render", "clear_color.3", 1.0));
}
