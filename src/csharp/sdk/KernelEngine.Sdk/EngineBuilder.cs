using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
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
/// Makes an engine of the default parts, each configured by the project file's section for it, with
/// any of the replaceable ones swapped for what a function given here makes from the parts before it.
/// </summary>
public sealed class EngineBuilder
{
    readonly string _projectDir;
    Func<EngineParts, IEnumerable<IDisposable>> _renderPasses = DefaultRenderPasses;
    Func<EngineParts, IEnumerable<IDisposable>> _physics = DefaultPhysics;
    Func<EngineParts, IEnumerable<IDisposable>> _audio = DefaultAudio;
    Microsoft.Extensions.Logging.ILoggerFactory? _logging;

    internal EngineBuilder(string projectDir) => _projectDir = projectDir.TrimEnd(Path.DirectorySeparatorChar);

    /// <summary>Replaces the render passes: <paramref name="make"/> returns the passes it made, which the engine releases.</summary>
    public EngineBuilder WithRenderPasses(Func<EngineParts, IEnumerable<IDisposable>> make)
    {
        _renderPasses = make;
        return this;
    }

    /// <summary>Replaces the physics: <paramref name="make"/> returns the parts it made, which the engine releases.</summary>
    public EngineBuilder WithPhysics(Func<EngineParts, IEnumerable<IDisposable>> make)
    {
        _physics = make;
        return this;
    }

    /// <summary>Replaces the audio: <paramref name="make"/> returns the parts it made, which the engine releases.</summary>
    public EngineBuilder WithAudio(Func<EngineParts, IEnumerable<IDisposable>> make)
    {
        _audio = make;
        return this;
    }

    /// <summary>Sends what every native library logs, and what every node logs, to <paramref name="loggerFactory"/>; without it native lines go to stderr.</summary>
    public EngineBuilder WithLogging(Microsoft.Extensions.Logging.ILoggerFactory loggerFactory)
    {
        _logging = loggerFactory;
        return this;
    }

    /// <summary>Makes every part and registers the engine's node types.</summary>
    public Engine Build()
    {
        var log = _logging;
        var owned = new List<IDisposable>();
        T Own<T>(T part) where T : IDisposable
        {
            owned.Add(part);
            return part;
        }

        var pool = Own(new EnkiTaskPool(log, uint.MaxValue));
        var files = Own(new StdFileSystem(log, "."));
        var io = Own(new PoolIo(log, pool, files));
        var config = Own(new DefaultConfiguration(log));
        Own(new ConfigurationTomlConfigurationSource(log, io)).Load(config, Path.Combine(_projectDir, "Project"));

        var input = Own(new Input.Input());
        var window = Own(new GlfwWindow(log, input,
            config.GetString("runtime.window", "title", "KernelEngine"),
            (int)config.GetInt("runtime.window", "width", 1280),
            (int)config.GetInt("runtime.window", "height", 720),
            config.GetBool("runtime.window", "fullscreen", false)));
        var ecs = Own(new FlecsEcsRegistry(log, 1048576));
        var fixedDt = (float)config.GetDouble("runtime", "fixed_dt", 1.0 / 60.0);
        var maxAccum = (float)config.GetDouble("runtime", "fixed_dt_max_accum", 0.25);
        var maxSystems = (uint)config.GetInt("runtime", "max_systems_per_phase", 256);
        var runtime = Own(new DefaultRuntime(log, ecs, pool, fixedDt, maxAccum, maxSystems));

        var gpu = Own(new WebgpuGpuDevice(log, null, false, false));
        var mailbox = config.GetString("runtime.renderer", "present_mode", "fifo") == "mailbox";
        var target = Own(new WebgpuWindowGpuRenderTarget(log, gpu, window, mailbox ? GpuPresentMode.Mailbox : GpuPresentMode.Fifo));
        var fonts = Own(new StbFontLoader(log, io));
        var assets = Own(new DefaultAssetResolver(log, null, fonts, _projectDir, io));
        var tree = Own(new DefaultSceneTree(log, ecs, runtime));

        var shaderDir = Path.Combine(AppContext.BaseDirectory, "shaders");
        var binder = Own(new GroupedRenderResourceBinder(log, gpu, shaderDir, io));
        var service = Own(new DefaultRenderService(log, gpu, target, ecs, io, binder, shaderDir, GpuTextureFormat.Rgba16Float, GpuTextureFormat.D32Float, Engine.ClearColor(config)));
        var viewSpace = Own(new RhViewSpace(log));
        var camera = Own(new DefaultRenderCamera(log, viewSpace, gpu));
        var scene = Own(new DefaultRenderSceneResolve(log, runtime, ecs, service));
        var frame = Own(new DefaultRenderFrame(log, runtime, ecs, service, camera, scene));

        var parts = new EngineParts
        {
            ProjectDir = _projectDir,
            Pool = pool,
            Io = io,
            Configuration = config,
            Input = input,
            Window = window,
            Ecs = ecs,
            Runtime = runtime,
            Gpu = gpu,
            Assets = assets,
            Tree = tree,
            Service = service,
            ViewSpace = viewSpace,
            Camera = camera,
            Scene = scene,
            Frame = frame,
            Logging = log,
            DefaultFont = Path.Combine(AppContext.BaseDirectory, "assets", "fonts", "LiberationSans-Regular.ttf"),
        };
        owned.AddRange(_renderPasses(parts));
        owned.AddRange(_physics(parts));
        owned.AddRange(_audio(parts));

        var actions = Own(new DefaultInputActions(log, runtime, input, config, "input"));
        var types = Own(new DefaultNodeTypes(log, runtime, ecs, tree, actions));
        Own(new DefaultSceneFiles(log, ecs, types, assets, io));
        types.RegisterEngineNodeTypes();
        return new Engine(parts, owned, types, log);
    }

    /// <summary>The default passes: shadows, clusters, the gbuffer, deferred and forward lighting, tonemapping, the UI and its labels.</summary>
    public static IEnumerable<IDisposable> DefaultRenderPasses(EngineParts p)
    {
        var log = p.Logging;
        var shadow = new RenderShadow(log, p.Runtime, p.Ecs, p.Service, p.Gpu, p.ViewSpace, p.Camera, p.Scene, p.Frame, 1024, 25.0f, 20.0f, 0.1f, 50.0f);
        var cluster = new RenderCluster(log, p.Runtime, p.Ecs, p.Service, p.Gpu, p.ViewSpace, p.Camera, p.Scene, p.Frame, 16, 9, 24, 64);
        var gbuffer = new RenderGbuffer(log, p.Runtime, p.Ecs, p.Service, p.Gpu, p.ViewSpace, p.Camera, p.Scene, p.Frame);
        var ui = new DefaultRenderUi(log, p.Runtime, p.Ecs, p.Service, p.Gpu, p.ViewSpace, p.Camera, p.Scene, p.Frame);
        return
        [
            shadow, cluster, gbuffer,
            new RenderDeferredLighting(log, p.Runtime, p.Ecs, p.Service, p.Gpu, p.ViewSpace, p.Camera, p.Scene, p.Frame, true, gbuffer.Resources, shadow.Resources, cluster.Resources),
            new RenderForward(log, p.Runtime, p.Ecs, p.Service, p.Gpu, p.ViewSpace, p.Camera, p.Scene, p.Frame, true, shadow.Resources, cluster.Resources),
            new RenderTonemap(log, p.Runtime, p.Ecs, p.Service, p.Gpu, p.ViewSpace, p.Camera, p.Scene, p.Frame),
            ui,
            new RenderLabelResolve(log, p.Runtime, p.Ecs, p.Service, p.Gpu, p.ViewSpace, p.Camera, p.Scene, p.Frame, ui, p.Assets, p.DefaultFont),
        ];
    }

    /// <summary>The default physics: a Box2D world with the gravity of <c>runtime.physics_2d</c>, and the module syncing bodies.</summary>
    public static IEnumerable<IDisposable> DefaultPhysics(EngineParts p)
    {
        var gx = (float)p.Configuration.GetDouble("runtime.physics_2d", "gravity_x", 0.0);
        var gy = (float)p.Configuration.GetDouble("runtime.physics_2d", "gravity_y", 0.0);
        var world = new Box2dPhysics2D(p.Logging, gx, gy);
        return [world, new Physics.PhysicsBody2dModule(p.Logging, p.Runtime, p.Ecs, world, p.Tree)];
    }

    /// <summary>The default audio: miniaudio, and the module playing the sound components.</summary>
    public static IEnumerable<IDisposable> DefaultAudio(EngineParts p)
    {
        var audio = new MiniaudioAudio(p.Logging, p.Io);
        return [audio, new Audio.SoundModule(p.Logging, p.Runtime, p.Ecs, audio, p.ProjectDir)];
    }
}
