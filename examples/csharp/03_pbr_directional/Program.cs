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

const float metal0 = 0.0f; const float rough0 = 0.8f;
const float metal1 = 1.0f; const float rough1 = 0.5f;
const float metal2 = 0.5f; const float rough2 = 0.5f;
const float metal3 = 0.2f; const float rough3 = 0.6f;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<INativeEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 03 PBR Directional"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new Vector4(0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 03_pbr_directional");
        Console.WriteLine("[KernelEngine] Features: pbr_ggx, directional_light, orbiting_light");

        tree.AddNode(new OrbitingLight { Color = Vector3.One, Intensity = 3.0f }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, NearPlane = 0.1f, FarPlane = 1000f }, "Camera");
        cam.Position = new Vector3(0f, 1.0f, 5.0f);

        var quad = KernelEngine.Render.MeshPrimitives.Quad(resources);
        var mat0 = resources.CreateMaterial("mat0", Vector4.One, metal0, rough0);
        var mat1 = resources.CreateMaterial("mat1", Vector4.One, metal1, rough1);
        var mat2 = resources.CreateMaterial("mat2", Vector4.One, metal2, rough2, shader: "stripes");
        var mat3 = resources.CreateMaterial("mat3", Vector4.One, metal3, rough3, shader: "checker");

        var n0 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat0 }, "QuadDielectric");
        n0.Position = new Vector3(-3f, 0f, 0f);

        var n1 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat1 }, "QuadMetal");
        n1.Position = new Vector3(-1f, 0f, 0f);

        var n2 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat2 }, "QuadStripes");
        n2.Position = new Vector3(1f, 0f, 0f);

        var n3 = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat3 }, "QuadChecker");
        n3.Position = new Vector3(3f, 0f, 0f);
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

sealed class OrbitingLight : DirectionalLight
{
    private float _angle;

    protected override bool HasBehavior => true;

    protected override void OnUpdate(in View view)
    {
        _angle += 60f * view.DeltaTime * MathF.PI / 180f;
        Direction = Vector3.Normalize(new Vector3(MathF.Sin(_angle), 1f, MathF.Cos(_angle)));
    }
}
