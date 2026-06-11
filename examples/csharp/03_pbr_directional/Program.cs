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

// 03_pbr_directional — three quads with different PBR materials lit by a
// directional light that orbits around them. Showcases the NodeBehavior
// surface: the orbiting light is a Node subclass with an OnUpdate(View)
// override; SceneRenderModule's BehaviorSystem ticks it every frame.

const float metal0 = 0.0f; const float rough0 = 0.8f;
const float metal1 = 1.0f; const float rough1 = 0.1f;
const float metal2 = 0.5f; const float rough2 = 0.5f;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 03 PBR Directional"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new SceneModule(tree =>
    {
        Console.WriteLine("[KernelEngine] Example: 03_pbr_directional");
        Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
        Console.WriteLine("[KernelEngine] Features: pbr_ggx, directional_light, orbiting_light");
        Console.WriteLine(
            $"[KernelEngine] PBR materials: " +
            $"dielectric(m={metal0:F1} r={rough0:F1})  " +
            $"metal(m={metal1:F1} r={rough1:F1})  " +
            $"mixed(m={metal2:F1} r={rough2:F1})");

        tree.AddNode(new OrbitingLight { Color = Vector3.One, Intensity = 3.0f }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 1.0f, 5.0f) };

        var mat0 = tree.Renderer.CreateMaterial(new Vector4(1f, 1f, 1f, 1f), metallic: metal0, roughness: rough0).Value;
        var mat1 = tree.Renderer.CreateMaterial(new Vector4(1f, 1f, 1f, 1f), metallic: metal1, roughness: rough1).Value;
        var mat2 = tree.Renderer.CreateMaterial(new Vector4(1f, 1f, 1f, 1f), metallic: metal2, roughness: rough2).Value;

        var n0 = tree.AddNode(new MeshRenderer { MaterialHandle = mat0 }, "QuadDielectric");
        n0.LocalTransform = n0.LocalTransform with { Position = new Vector3(-2f, 0f, 0f) };

        tree.AddNode(new MeshRenderer { MaterialHandle = mat1 }, "QuadMetal");

        var n2 = tree.AddNode(new MeshRenderer { MaterialHandle = mat2 }, "QuadMixed");
        n2.LocalTransform = n2.LocalTransform with { Position = new Vector3(2f, 0f, 0f) };
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[03_pbr_directional] Loop running. Close the window to exit.");

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
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Lights: 0p 0s 1d");
        frameCount     = 0;
        fpsWindowStart = now;
    }
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
