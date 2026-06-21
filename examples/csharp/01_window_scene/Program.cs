using System.Diagnostics;
using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;
using KernelEngine.Render;

// 01_window_scene â€” a single orange quad spinning on the screen under a fixed
// directional light. Smallest possible scene that exercises window + renderer
// + framework + a scripted node behavior.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine â€” 01 Window/Tree"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.15f, 0.15f, 0.15f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new PostProcessModule(tonemapping: true))
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        var renderer = sp.GetRequiredService<IRenderer>();
        Console.WriteLine("[KernelEngine] Example: 01_window_scene");
        Console.WriteLine("[KernelEngine] Features: window, renderer, single_quad, spinner_behavior");

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1f, 0.5f)),
            Color     = Vector3.One,
            Intensity = 2f,
        }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 5f) };

        var orangeMat = renderer.CreateMaterial(new Vector4(1f, 0.5f, 0f, 1f));
        tree.AddNode(new SpinningQuad { MaterialHandle = orangeMat }, "Spinner");
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[01_window_scene] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
int frameCount = 0;
double fpsWindowStart = 0;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;

    frameCount++;
    if (now - fpsWindowStart >= 5.0)
    {
        double fps = frameCount / (now - fpsWindowStart);
        Console.WriteLine($"[Example 01] FPS: {fps:F2}");
        frameCount     = 0;
        fpsWindowStart = now;
    }
}

runtime.UnloadModules(sp);

Console.WriteLine("[01_window_scene] Exited cleanly.");

// â”€â”€ A MeshRenderer that spins around Y at 90 deg/s â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

sealed class SpinningQuad : MeshRenderer
{
    private float _angle;

    protected override void OnUpdate(in View view)
    {
        _angle += 90f * view.DeltaTime;
        if (_angle >= 360f) _angle -= 360f;

        LocalTransform = LocalTransform with
        {
            Rotation = Quaternion.CreateFromYawPitchRoll(_angle * MathF.PI / 180f, 0f, 0f),
        };
    }
}
