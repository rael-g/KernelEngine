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

// 07_point_lights — a 6×6 quad grid lit by four moving colored point lights, no
// directional light. Render v2 (webgpu): the forward pass accumulates each
// PointLightComponent (position from its transform) with distance attenuation;
// an AmbientLight fills the unlit areas.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 07 Point Lights"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.02f, 0.02f, 0.02f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 07_point_lights");
        Console.WriteLine("[KernelEngine] Features: point_lights, multi_light_accumulation");

        tree.AddNode(new AmbientLight { Color = new(0.01f, 0.01f, 0.01f) }, "Ambient");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 2f, 15f) };

        var quad = KernelEngine.Render.MeshPrimitives.Quad(resources);
        var mat  = resources.CreateMaterial(Vector4.One, metallic: 0.1f, roughness: 0.5f);

        // Grid of quads at z=0, x,y ∈ {-5, -3, -1, 1, 3, 5}.
        for (int x = -5; x <= 5; x += 2)
        for (int y = -5; y <= 5; y += 2)
        {
            var n = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat }, $"Quad_{x}_{y}");
            n.LocalTransform = n.LocalTransform with { Position = new Vector3(x, y, 0f) };
        }

        var colors = new[] { Vector3.UnitX, Vector3.UnitY, Vector3.UnitZ, new Vector3(1f, 1f, 0f) };
        for (int i = 0; i < 4; i++)
        {
            tree.AddNode(new MovingPointLight
            {
                Color     = colors[i],
                Intensity = 5f,
                Radius    = 15f,
                Phase     = i * (MathF.PI / 2f),
            }, $"PointLight_{i}");
        }
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[07_point_lights] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[07_point_lights] Exited cleanly.");

// ── Moving point light — orbits the origin with per-instance phase ───────────

sealed class MovingPointLight : PointLight
{
    public float Phase { get; init; }

    private float _time;

    protected override void OnUpdate(in View view)
    {
        _time += view.DeltaTime;
        float x = MathF.Cos(_time + Phase) * 5f;
        float y = MathF.Sin(_time + Phase) * 5f;
        float z = MathF.Sin(_time * 0.5f) * 2f + 2f;
        LocalTransform = LocalTransform with { Position = new Vector3(x, y, z) };
    }
}
