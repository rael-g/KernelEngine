using KernelEngine.Audio;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Logger;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;

using Pong;

var services = new ServiceCollection()
    .AddProjectConfig()
    .AddConfig<GlfwWindowConfig>("runtime.window")
    .AddConfig<Box2dPhysics2DConfig>("runtime.physics_2d")
    .AddConfig<WebgpuWindowGpuRenderTargetConfig>("runtime.renderer")
    .AddLogger()
    .AddConsoleSink(LogLevel.Warning)
    .AddInput()
    .AddBox2dPhysics2D()
    .AddMiniaudioAudio()
    .AddAudioScene()
    .AddAudioComponentsNodeTypes()
    .AddStbFontLoader()
    .AddAssetResolver()
    .AddInputActions()
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .AddConfig<DefaultRenderServiceConfig>("render", config => config with { ShaderDir = ExamplePaths.ShaderDir })
    .Add<IRuntimeModule>(new WebgpuRenderModule())
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule(_ => { }))
    .Add<IRuntimeModule>(new KernelEngine.Physics.Body2DModule())
    .Add<IRuntimeModule>(new PongModule())
    .Add<IRuntimeModule>(new SceneRouterModule());

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    window.PollEvents();
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}
runtime.UnloadModules();
