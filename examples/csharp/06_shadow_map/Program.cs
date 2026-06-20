using System.Diagnostics;
using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// 06_shadow_map â€” directional shadow casting onto a floor plane. A red cube
// sits above a gray floor; the sun's azimuth sweeps over time so the cube's
// shadow slides across the floor, making the shadow projection visible at a
// glance.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine â€” 06 Shadow Map"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.1f, 0.1f, 0.15f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new ShadowModule(resolution: 1024, frustumSize: 20f, farPlane: 50f))
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        var renderer = sp.GetRequiredService<IRenderer>();
        Console.WriteLine("[KernelEngine] Example: 06_shadow_map");
        Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
        Console.WriteLine("[KernelEngine] Features: shadow_map_directional, ortho_light_frustum, animated_sun");

        var planeMesh = MeshPrimitives.Plane(renderer);
        var cubeMesh  = MeshPrimitives.Cube(renderer);

        var floorMat = renderer.CreateMaterial(new Vector4(0.5f, 0.5f, 0.5f, 1f), roughness: 0.8f);
        var redMat   = renderer.CreateMaterial(new Vector4(0.8f, 0.2f, 0.2f, 1f), metallic: 0.2f, roughness: 0.3f);

        tree.AddNode(new AnimatedSun
        {
            Color     = Vector3.One,
            Intensity = 10f,
            Ambient   = new(0.15f, 0.15f, 0.15f),
        }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with
        {
            Position = new Vector3(0f, 5f, 10f),
            Rotation = Quaternion.CreateFromYawPitchRoll(0f, -25f * MathF.PI / 180f, 0f),
        };

        var floor = tree.AddNode(new MeshRenderer { MeshHandle = planeMesh, MaterialHandle = floorMat }, "Floor");
        floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(20f, 1f, 20f) };

        var caster = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = redMat }, "Caster");
        caster.LocalTransform = caster.LocalTransform with { Position = new Vector3(0f, 1f, 0f) };
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[06_shadow_map] Loop running. Close the window to exit.");

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
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}");
        frameCount     = 0;
        fpsWindowStart = now;
    }
}

runtime.UnloadModules(sp);

Console.WriteLine("[06_shadow_map] Exited cleanly.");

// â”€â”€ Animated sun â€” direction sweeps in azimuth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

sealed class AnimatedSun : DirectionalLight
{
    private float _t;

    protected override void OnUpdate(in View view)
    {
        _t += view.DeltaTime;
        float a = MathF.Sin(_t * 0.8f);
        Direction = Vector3.Normalize(new Vector3(a * 0.8f, 1.0f, 0.5f));
    }
}
