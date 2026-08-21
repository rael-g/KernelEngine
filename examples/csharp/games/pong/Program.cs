using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using Pong;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;
using KernelEngine.Audio;
using KernelEngine.Input;

var services = new ServiceCollection()
    .AddProjectConfig()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddBox2D()
    .AddMiniAudio()
    .AddTextStbTrueType()
    .AddAssetResolver()
    .AddInputActions<PongAction>()
    .Add<INativeEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule(_ => { }))
    .Add<IRuntimeModule>(new KernelEngine.Physics.Body2DModule())
    .Add<IRuntimeModule>(new PongModule())
    .Add<IRuntimeModule>(new SceneRouterModule(sceneModuleDependency: typeof(SceneNodesModule)));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);
