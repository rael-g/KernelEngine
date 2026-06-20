using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using Pong;

// Pong — driven by Project + actions.input + scenes/Main.scene. Program.cs
// just wires the engine modules and points the scene loader at Main.scene;
// everything visible — the field layout, the scripts, the input bindings —
// lives in the data files.

var services = new ServiceCollection()
    .AddKernel()
    .AddProjectConfig()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddBox2D()
    .AddMiniAudio()
    .AddTextStbTrueType()
    .AddInputActions<PongAction>()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .Add<IRuntimeModule>(new BgfxRenderModule())
        .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new PongModule())
    .Add<IRuntimeModule>(new SceneRouterModule());  // initial scene comes from Project's default_scene

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
