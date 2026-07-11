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

// 08_spot_lights — three colored spot lights orbiting above a floor + grid of
// cubes. Each spot's direction tracks the origin so the cones sweep across the
// floor and cubes. Render v2 (webgpu): the forward pass accumulates each
// SpotLightComponent (position from its transform, direction explicit) with
// distance × cone falloff.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 08 Spot Lights"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.01f, 0.01f, 0.01f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 08_spot_lights");
        Console.WriteLine("[KernelEngine] Features: spot_lights, multi_light_accumulation, cone_falloff");

        tree.AddNode(new AmbientLight { Color = new(0.01f, 0.01f, 0.01f) }, "Ambient");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 5f, 15f) };

        var planeMesh = KernelEngine.Render.MeshPrimitives.Plane(resources);
        var cubeMesh  = KernelEngine.Render.MeshPrimitives.Cube(resources);

        var floorMat = resources.CreateMaterial("floor", new Vector4(0.3f, 0.3f, 0.3f, 1f), roughness: 0.8f);
        var cubeMat  = resources.CreateMaterial("cube", new Vector4(0.8f, 0.8f, 0.8f, 1f), metallic: 0.1f, roughness: 0.5f);

        var floor = tree.AddNode(new MeshRenderer { MeshHandle = planeMesh, MaterialHandle = floorMat }, "Floor");
        floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(30f, 1f, 30f) };

        for (int x = -4; x <= 4; x += 4)
        for (int z = -4; z <= 4; z += 4)
        {
            var n = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = cubeMat }, $"Cube_{x}_{z}");
            n.LocalTransform = n.LocalTransform with { Position = new Vector3(x, 1f, z) };
        }

        (Vector3 color, float offset)[] spots =
        [
            (new(1f, 0f, 0f), 0f),
            (new(0f, 1f, 0f), MathF.PI * 2f / 3f),
            (new(0f, 0f, 1f), MathF.PI * 4f / 3f),
        ];
        foreach (var (color, offset) in spots)
        {
            tree.AddNode(new OrbitingSpot
            {
                Color         = color,
                Intensity     = 25f,
                Range         = 60f,
                InnerAngleDeg = 12f,
                OuterAngleDeg = 25f,
                Offset        = offset,
            }, $"Spot_{color}");
        }
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[08_spot_lights] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[08_spot_lights] Exited cleanly.");

// ── Orbiting spot light — position circles, direction points at the origin ───

sealed class OrbitingSpot : SpotLight
{
    public float Offset { get; init; }

    private float _time;

    protected override void OnUpdate(in View view)
    {
        _time += view.DeltaTime;
        float x = MathF.Cos(_time + Offset) * 8f;
        float z = MathF.Sin(_time + Offset) * 8f;
        LocalTransform = LocalTransform with { Position = new Vector3(x, 10f, z) };
        Direction = Vector3.Normalize(-LocalTransform.Position);
    }
}
