using System.Diagnostics;
using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// 09_many_lights — stress test: 121-cube wall lit by 200 randomly moving
// colored point lights. Tests the contributor's per-frame light loop and the
// renderer's per-frame light cap (lights past the cap are dropped silently —
// behavior we want visible at this scale).

const int LightCount = 200;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 09 Many Lights Stress Test"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.01f, 0.01f, 0.01f, 1.0f)))
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new SceneModule(tree =>
    {
        Console.WriteLine("[KernelEngine] Example: 09_many_lights");
        Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
        Console.WriteLine($"[KernelEngine] Features: stress_test, {LightCount} point_lights");

        tree.AddNode(new AmbientLight { Color = new(0.01f, 0.01f, 0.01f) }, "Ambient");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 30f) };

        var cubeMesh = MeshPrimitives.Cube(tree.Renderer);
        var mat = tree.Renderer.CreateMaterial(Vector4.One, metallic: 0.1f, roughness: 0.5f).Value;

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
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Lights: {LightCount}p 0s 0d");
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
