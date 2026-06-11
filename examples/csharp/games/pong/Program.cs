using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
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
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .Add<IRuntimeModule>(new BgfxRenderModule())
    .Add<IRuntimeModule>(new SceneRenderModule())
    // Pong scripts the SceneLoader will instantiate.
    .AddNodeType<Wall>("Pong.Wall")
    .AddNodeType<Paddle>("Pong.Paddle")
    .AddNodeType<Ball>("Pong.Ball")
    .AddNodeType<Scoreboard>("Pong.Scoreboard")
    .AddNodeType<PhysicsDriver>("Pong.PhysicsDriver")
    // Shared materials + sounds; lazy-created on first resolution so the
    // factory runs INSIDE the render-worker-pinned SceneModule callback.
    .AddSingleton<PongResources>()
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        var loader = sp.GetRequiredService<SceneLoader>();
        loader.LoadInto(tree, sp, Path.Combine(AppContext.BaseDirectory, "scenes", "Main.scene"));
    }));

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
