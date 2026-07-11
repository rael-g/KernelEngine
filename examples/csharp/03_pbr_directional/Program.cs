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

// 03_pbr_directional — three quads with different PBR materials lit by a
// directional light that orbits around them. Render v2 (webgpu): Cook-Torrance
// GGX in the forward pass; the orbiting light is a Node subclass whose OnUpdate
// rewrites its DirectionalLightComponent, which the per-frame uniform reads.

const float metal0 = 0.0f; const float rough0 = 0.8f;
const float metal1 = 1.0f; const float rough1 = 0.1f;
const float metal2 = 0.5f; const float rough2 = 0.5f;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 03 PBR Directional"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 03_pbr_directional");
        Console.WriteLine("[KernelEngine] Features: pbr_ggx, directional_light, orbiting_light");

        tree.AddNode(new OrbitingLight { Color = Vector3.One, Intensity = 3.0f }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 1.0f, 5.0f) };

        var quad = KernelEngine.Render.MeshPrimitives.Quad(resources);
        var mat0 = resources.CreateMaterial("mat0", Vector4.One, metal0, rough0);
        var mat1 = resources.CreateMaterial("mat1", Vector4.One, metal1, rough1);
        var mat2 = resources.CreateMaterial("mat2", Vector4.One, metal2, rough2);

        var n0 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat0 }, "QuadDielectric");
        n0.LocalTransform = n0.LocalTransform with { Position = new Vector3(-2f, 0f, 0f) };

        tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat1 }, "QuadMetal");

        var n2 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat2 }, "QuadMixed");
        n2.LocalTransform = n2.LocalTransform with { Position = new Vector3(2f, 0f, 0f) };
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[03_pbr_directional] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[03_pbr_directional] Exited cleanly.");

// ── Orbiting directional light ───────────────────────────────────────────────

sealed class OrbitingLight : DirectionalLight
{
    private float _angle;

    protected override void OnUpdate(in View view)
    {
        _angle += 60f * view.DeltaTime * MathF.PI / 180f;
        Direction = Vector3.Normalize(new Vector3(MathF.Sin(_angle), 1f, MathF.Cos(_angle)));
    }
}
