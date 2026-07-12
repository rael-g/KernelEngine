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

// 03_pbr_directional — four quads with different PBR materials lit by a
// directional light that orbits around them. Render v2 (webgpu): Cook-Torrance
// GGX in the forward pass; the orbiting light is a Node subclass whose OnUpdate
// rewrites its DirectionalLightComponent, which the per-frame uniform reads.
// Also exercises every category of authored material: the engine default
// ("standard", QuadDielectric/QuadMetal), an engine-shipped non-default
// ("stripes", QuadStripes), and an EXAMPLE-owned material this project
// authors itself (materials/checker.slang, QuadChecker) — proving a
// downstream game can add its own IMaterial shader without touching the
// engine's src/shaders/materials/ tree at all.

const float metal0 = 0.0f; const float rough0 = 0.8f;
const float metal1 = 1.0f; const float rough1 = 0.5f;
const float metal2 = 0.5f; const float rough2 = 0.5f;
const float metal3 = 0.2f; const float rough3 = 0.6f;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 03 PBR Directional"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../../build/win/bin/shaders")), clearColor: new Vector4(0.05f, 0.05f, 0.05f, 1.0f)))
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
        // Selects the authored "stripes" material (src/shaders/materials/stripes.slang,
        // engine-shipped) — a real shader difference, resolving to its own PSO,
        // not just different UBO data. mat0/mat1 use the engine default ("standard").
        var mat2 = resources.CreateMaterial("mat2", Vector4.One, metal2, rough2, shader: "stripes");
        // Selects "checker" — a material this EXAMPLE owns (materials/checker.slang,
        // next to this Program.cs, outside the engine's src/ tree entirely) and the
        // engine never shipped. Proves a downstream project can author its own
        // IMaterial shader, not just pick between engine-provided ones.
        var mat3 = resources.CreateMaterial("mat3", Vector4.One, metal3, rough3, shader: "checker");

        var n0 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat0 }, "QuadDielectric");
        n0.LocalTransform = n0.LocalTransform with { Position = new Vector3(-3f, 0f, 0f) };

        var n1 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat1 }, "QuadMetal");
        n1.LocalTransform = n1.LocalTransform with { Position = new Vector3(-1f, 0f, 0f) };

        var n2 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat2 }, "QuadStripes");
        n2.LocalTransform = n2.LocalTransform with { Position = new Vector3(1f, 0f, 0f) };

        var n3 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat3 }, "QuadChecker");
        n3.LocalTransform = n3.LocalTransform with { Position = new Vector3(3f, 0f, 0f) };
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
