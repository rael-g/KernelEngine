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

// 10_hdr_bloom — single cube lit by an extremely bright orange directional
// light. Bloom + ACES tonemapping turn the over-bright surface into a
// glowing highlight that bleeds into neighboring pixels.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 10 HDR & Bloom"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.01f, 0.01f, 0.01f, 1.0f)))
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new PostProcessModule(
        tonemapping: true, tonemappingExposure: 1.0f, tonemappingGamma: 2.2f,
        bloom:       true, bloomThreshold:      0.8f, bloomIntensity:   1.5f))
    .Add<IRuntimeModule>(new SceneModule(tree =>
    {
        Console.WriteLine("[KernelEngine] Example: 10_hdr_bloom");
        Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
        Console.WriteLine("[KernelEngine] Features: hdr_rendering, bloom, aces_tonemapping");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 10f) };

        var cubeMesh = MeshPrimitives.Cube(tree.Renderer);
        var mat      = tree.Renderer.CreateMaterial(Vector4.One, metallic: 0.1f, roughness: 0.5f).Value;

        var glow = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = mat }, "GlowCube");
        glow.LocalTransform = glow.LocalTransform with { Scale = new Vector3(2f, 2f, 2f) };

        // Direction points toward the +Z hemisphere (light comes from +Z) so
        // the cube's front face catches a very high-intensity orange light —
        // pixel output goes well past 1.0, triggering the bloom threshold.
        tree.AddNode(new DirectionalLight
        {
            Direction = new Vector3(0f, 0f, 1f),
            Color     = new Vector3(1f, 0.5f, 0.2f),
            Intensity = 50f,
        }, "BrightSun");
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[10_hdr_bloom] Loop running. Close the window to exit.");

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

Console.WriteLine("[10_hdr_bloom] Exited cleanly.");
