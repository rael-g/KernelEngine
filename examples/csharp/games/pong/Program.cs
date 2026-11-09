using System.Diagnostics;
using System.Numerics;

using KernelEngine.Audio;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Physics;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.View;
using KernelEngine.Window.Glfw;

using Pong;

var projectDir = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
var shaderDir = Path.Combine(projectDir, "shaders");
var font = Path.Combine(projectDir, "assets", "fonts", "LiberationSans-Regular.ttf");

using var pool = new EnkiTaskPool(uint.MaxValue);
using var files = new StdFileSystem(".");
using var io = new PoolIo(pool, files);

using var config = new DefaultConfiguration();
using var toml = new ConfigurationTomlConfigurationSource(io);
toml.Load(config, Path.Combine(projectDir, "Project"));

using var input = new Input();
using var window = new GlfwWindow(input,
    config.GetString("runtime.window", "title", "Pong"),
    (int)config.GetInt("runtime.window", "width", 1280),
    (int)config.GetInt("runtime.window", "height", 720),
    config.GetBool("runtime.window", "fullscreen", false));

using var ecs = new FlecsEcsRegistry(1048576);
using var runtime = new DefaultRuntime(ecs, pool, 1.0f / 60.0f, 0.25f, 256);

using var gpu = new WebgpuGpuDevice(null, false, false);
var mailbox = config.GetString("runtime.renderer", "present_mode", "fifo") == "mailbox";
using var target = new WebgpuWindowGpuRenderTarget(gpu, window, mailbox ? GpuPresentMode.Mailbox : GpuPresentMode.Fifo);

using var fonts = new StbFontLoader(io);
using var assets = new DefaultAssetResolver(null, fonts, projectDir, io);
using var tree = new DefaultSceneTree(ecs, runtime);

using var binder = new GroupedRenderResourceBinder(gpu, shaderDir, io);
var clearColor = new Vector4(
    (float)config.GetDouble("render", "clear_color.0", 0.0),
    (float)config.GetDouble("render", "clear_color.1", 0.0),
    (float)config.GetDouble("render", "clear_color.2", 0.0),
    (float)config.GetDouble("render", "clear_color.3", 1.0));
using var service = new DefaultRenderService(gpu, target, ecs, io, binder, shaderDir, GpuTextureFormat.Rgba16Float, GpuTextureFormat.D32Float, clearColor);
using var viewSpace = new RhViewSpace();
using var camera = new DefaultRenderCamera(viewSpace, gpu);
using var scene = new DefaultRenderSceneResolve(runtime, ecs, service);
using var frame = new DefaultRenderFrame(runtime, ecs, service, camera, scene);
using var shadow = new RenderShadow(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, 1024, 25.0f, 20.0f, 0.1f, 50.0f);
using var cluster = new RenderCluster(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, 16, 9, 24, 64);
using var gbuffer = new RenderGbuffer(runtime, ecs, service, gpu, viewSpace, camera, scene, frame);
using var deferred = new RenderDeferredLighting(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, true, gbuffer.Resources, shadow.Resources, cluster.Resources);
using var forward = new RenderForward(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, true, shadow.Resources, cluster.Resources);
using var tonemap = new RenderTonemap(runtime, ecs, service, gpu, viewSpace, camera, scene, frame);
using var ui = new DefaultRenderUi(runtime, ecs, service, gpu, viewSpace, camera, scene, frame);
using var labels = new RenderLabelResolve(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, ui, assets, font);

using var physics = new Box2dPhysics2D(
    (float)config.GetDouble("runtime.physics_2d", "gravity_x", 0.0),
    (float)config.GetDouble("runtime.physics_2d", "gravity_y", 0.0));
using var bodies = new PhysicsBody2dModule(runtime, ecs, physics, tree);

using var audio = new MiniaudioAudio(io);
using var sounds = new SoundModule(runtime, ecs, audio, projectDir);

using var actions = new DefaultInputActions(runtime, input, config, "input");
using var types = new DefaultNodeTypes(runtime, ecs, tree, actions);
using var scenes = new DefaultSceneFiles(ecs, types, assets, io);

EngineNodeTypes.Register(types);
var game = new Game(types);

game.OpenSlot((INativeEcsCommands)runtime.Commands(), $"res://scenes/{config.GetString("project", "default_scene", "Menu")}.scene.toml");

var clock = Stopwatch.StartNew();
var previous = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose() && !runtime.ExitRequested())
{
    window.PollEvents();
    var current = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(current - previous));
    previous = current;
}
runtime.Flush();
runtime.UnloadModules();
