using System.Diagnostics;
using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;
using KernelEngine.Render;

// 09_many_lights — stress test: an 11×11 cube wall lit by 200 randomly moving
// colored point lights. Render v2 (webgpu): a clustered forward pipeline — a
// compute pass bins the lights into a 16×8×24 froxel grid, and the forward only
// shades each fragment with the lights in its cluster.

const int LightCount = 200;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 09 Many Lights Stress Test"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.01f, 0.01f, 0.01f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 09_many_lights");
        Console.WriteLine($"[KernelEngine] Features: clustered_forward, {LightCount} point_lights");

        tree.AddNode(new AmbientLight { Color = new(0.01f, 0.01f, 0.01f) }, "Ambient");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 30f) };

        var cubeMesh = KernelEngine.Render.MeshPrimitives.Cube(resources);
        var mat = resources.CreateMaterial(Vector4.One, metallic: 0.1f, roughness: 0.5f);

        // 11×11 cube wall facing the camera (z=0).
        for (int x = -15; x <= 15; x += 3)
        for (int y = -15; y <= 15; y += 3)
        {
            var n = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = mat }, $"Cube_{x}_{y}");
            n.LocalTransform = n.LocalTransform with { Position = new Vector3(x, y, 0f) };
        }

        // Fixed-seed PRNG so the visual is deterministic across runs.
        var rand = new Random(42);
        for (int i = 0; i < LightCount; i++)
        {
            tree.AddNode(new RandomMovingLight(rand)
            {
                Color     = new Vector3((float)rand.NextDouble(), (float)rand.NextDouble(), (float)rand.NextDouble()),
                Intensity = 2f + (float)rand.NextDouble() * 3f,
                Radius    = 5f + (float)rand.NextDouble() * 10f,
                Speed     = 0.5f + (float)rand.NextDouble() * 2f,
            }, $"Light_{i}");
        }
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[09_many_lights] Loop running. Close the window to exit.");

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
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Lights: {LightCount}p");
        frameCount     = 0;
        fpsWindowStart = now;
    }
}

runtime.UnloadModules(sp);

Console.WriteLine("[09_many_lights] Exited cleanly.");

// ── Random moving point light — per-instance seed picked at construction ─────

sealed class RandomMovingLight : PointLight
{
    public float Speed { get; init; } = 1f;

    private readonly Vector3 _seed;
    private float _time;

    public RandomMovingLight(Random rand)
    {
        _seed = new Vector3(
            (float)rand.NextDouble() * 100f,
            (float)rand.NextDouble() * 100f,
            (float)rand.NextDouble() * 100f);
    }

    protected override void OnUpdate(in View view)
    {
        _time += view.DeltaTime * Speed;
        float x = MathF.Sin(_time + _seed.X) * 15f;
        float y = MathF.Cos(_time + _seed.Y) * 15f;
        float z = MathF.Sin(_time * 0.7f + _seed.Z) * 5f + 5f;
        LocalTransform = LocalTransform with { Position = new Vector3(x, y, z) };
    }
}
