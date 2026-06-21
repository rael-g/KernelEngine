using System.Diagnostics;
using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;
using KernelEngine.Render;

// 11_ssao â€” 7Ã—4 cube wall on a floor. SSAO is requested via PostProcessModule
// but the bgfx backend's SSAO path is currently a no-op (Kanban OBS.4/Z3), so
// any contact darkening visible is from the directional light, not ambient
// occlusion. The scene is kept for the moment it works.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine â€” 11 SSAO"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.2f, 0.2f, 0.2f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new ShadowModule(resolution: 1024, frustumSize: 20f, farPlane: 50f))
    .Add<IRuntimeModule>(new PostProcessModule(
        ssao: true, ssaoRadius: 0.5f, ssaoBias: 0.025f, ssaoStrength: 2.0f))
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        var renderer = sp.GetRequiredService<IRenderer>();
        Console.WriteLine("[KernelEngine] Example: 11_ssao");
        Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
        Console.WriteLine("[KernelEngine] Features: ssao (backend stub â€” see Kanban Z3)");

        tree.AddNode(new AmbientLight { Color = new(0.3f, 0.3f, 0.3f) }, "Ambient");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        var eye    = new Vector3(6f, 5f, 9f);
        var target = new Vector3(0f, 2f, 0f);
        var lookRot = Quaternion.CreateFromRotationMatrix(
            Matrix4x4.CreateWorld(eye, Vector3.Normalize(target - eye), Vector3.UnitY));
        cam.LocalTransform = cam.LocalTransform with { Position = eye, Rotation = lookRot };

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new Vector3(0.4f, 1f, 0.6f)),
            Color     = Vector3.One,
            Intensity = 4f,
        }, "Sun");

        var planeMesh = MeshPrimitives.Plane(renderer);
        var cubeMesh  = MeshPrimitives.Cube(renderer);
        var mat       = renderer.CreateMaterial(new Vector4(0.7f, 0.7f, 0.7f, 1f), roughness: 0.5f);

        var floor = tree.AddNode(new MeshRenderer { MeshHandle = planeMesh, MaterialHandle = mat }, "Floor");
        floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(10f, 1f, 10f) };

        for (int x = -3; x <= 3; x += 1)
        for (int y =  1; y <= 4; y += 1)
        {
            var n = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = mat }, $"Cube_{x}_{y}");
            n.LocalTransform = n.LocalTransform with
            {
                Position = new Vector3(x, y, 0f),
                Scale    = new Vector3(0.9f, 0.9f, 0.9f),
            };
        }
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[11_ssao] Loop running. Close the window to exit.");

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

Console.WriteLine("[11_ssao] Exited cleanly.");
