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

int LightCount = int.TryParse(Environment.GetEnvironmentVariable("LIGHT_COUNT"), out var lc) ? lc : 10000;
bool EnableShadows = Environment.GetEnvironmentVariable("ENABLE_SHADOWS") != "0";
bool EnableIbl = Environment.GetEnvironmentVariable("ENABLE_IBL") != "0";
const float CorridorWidth = 10f;
const float CorridorHeight = 6f;
const float CorridorLength = 300f;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 09 Many Lights Stress Test"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new Vector4(0.005f, 0.005f, 0.008f, 1.0f),
        clusterGridZ: 64, maxLightsPerCluster: 512, enableShadows: EnableShadows, enableIbl: EnableIbl))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 09_many_lights");
        Console.WriteLine($"[KernelEngine] Features: clustered_forward, {LightCount} point_lights, corridor length {CorridorLength:F0}");

        tree.AddNode(new AmbientLight { Color = new(0.01f, 0.01f, 0.01f) }, "Ambient");

        var cam = tree.AddNode(new Camera { Fov = 70f, NearPlane = 0.1f, FarPlane = CorridorLength + 50f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, -3f) };

        var cubeMesh = KernelEngine.Render.MeshPrimitives.Cube(resources);
        var wallMat = resources.CreateMaterial("wall", new Vector4(0.6f, 0.6f, 0.65f, 1f), metallic: 0.1f, roughness: 0.7f);

        float halfW = CorridorWidth / 2f;
        float halfH = CorridorHeight / 2f;
        float halfL = CorridorLength / 2f;

        var floor = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = wallMat }, "Floor");
        floor.LocalTransform = floor.LocalTransform with { Position = new Vector3(0f, -halfH, halfL), Scale = new Vector3(CorridorWidth, 1f, CorridorLength) };

        var ceiling = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = wallMat }, "Ceiling");
        ceiling.LocalTransform = ceiling.LocalTransform with { Position = new Vector3(0f, halfH, halfL), Scale = new Vector3(CorridorWidth, 1f, CorridorLength) };

        var wallLeft = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = wallMat }, "WallLeft");
        wallLeft.LocalTransform = wallLeft.LocalTransform with { Position = new Vector3(-halfW, 0f, halfL), Scale = new Vector3(1f, CorridorHeight, CorridorLength) };

        var wallRight = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = wallMat }, "WallRight");
        wallRight.LocalTransform = wallRight.LocalTransform with { Position = new Vector3(halfW, 0f, halfL), Scale = new Vector3(1f, CorridorHeight, CorridorLength) };

        var rand = new Random(42);
        for (int i = 0; i < LightCount; i++)
        {
            var anchor = new Vector3(
                (float)(rand.NextDouble() * 2.0 - 1.0) * (halfW - 1.5f),
                (float)(rand.NextDouble() * 2.0 - 1.0) * (halfH - 1.5f),
                5f + (i + 0.5f) / LightCount * (CorridorLength - 10f));

            tree.AddNode(new CorridorLight(rand, anchor)
            {
                Color     = new Vector3((float)rand.NextDouble(), (float)rand.NextDouble(), (float)rand.NextDouble()),
                Intensity = 2f + (float)rand.NextDouble() * 3f,
                Radius    = 4f + (float)rand.NextDouble() * 4f,
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
        double frameMs = fps > 0 ? 1000.0 / fps : 0.0;
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2} ({frameMs:F2} ms/frame)  Lights: {LightCount}p");
        frameCount     = 0;
        fpsWindowStart = now;
    }
}

runtime.UnloadModules(sp);

Console.WriteLine("[09_many_lights] Exited cleanly.");

sealed class CorridorLight : PointLight
{
    public float Speed { get; init; } = 1f;

    private readonly Vector3 _anchor;
    private readonly Vector3 _seed;
    private float _time;

    public CorridorLight(Random rand, Vector3 anchor)
    {
        _anchor = anchor;
        _seed = new Vector3(
            (float)rand.NextDouble() * 100f,
            (float)rand.NextDouble() * 100f,
            (float)rand.NextDouble() * 100f);
    }

    protected override bool HasBehavior => true;

    protected override void OnUpdate(in View view)
    {
        _time += view.DeltaTime * Speed;
        float dx = MathF.Sin(_time + _seed.X) * 0.8f;
        float dy = MathF.Cos(_time + _seed.Y) * 0.8f;
        float dz = MathF.Sin(_time * 0.7f + _seed.Z) * 0.5f;
        LocalTransform = LocalTransform with { Position = _anchor + new Vector3(dx, dy, dz) };
    }
}
