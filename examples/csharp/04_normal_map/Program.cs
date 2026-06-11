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

// 04_normal_map — two quads side by side; the right one carries a procedural
// ripple normal map, the left has the same material without it. Highlights
// how a tangent-space normal map perturbs the lighting compared to the flat
// surface (look at the specular highlight as the static directional light
// rakes across both quads).

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 04 Normal Map"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new SceneModule(tree =>
    {
        Console.WriteLine("[KernelEngine] Example: 04_normal_map");
        Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
        Console.WriteLine("[KernelEngine] Features: normal_map, tbn, tangent_space, pbr_ggx");

        // Procedural ripple normal map (128×128) — each texel encodes a unit
        // normal in tangent space, mapped to RGB via N = (n + 1) / 2.
        const uint w = 128, h = 128;
        var pixels = new byte[w * h * 4];
        for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            float nx = MathF.Sin(x / 8.0f * 2f * MathF.PI);
            float ny = MathF.Cos(y / 8.0f * 2f * MathF.PI);
            float nz = 1.0f;
            float inv = 1f / MathF.Sqrt(nx * nx + ny * ny + nz * nz);
            nx *= inv; ny *= inv; nz *= inv;
            int i = (y * (int)w + x) * 4;
            pixels[i]     = (byte)((nx * 0.5f + 0.5f) * 255);
            pixels[i + 1] = (byte)((ny * 0.5f + 0.5f) * 255);
            pixels[i + 2] = (byte)((nz * 0.5f + 0.5f) * 255);
            pixels[i + 3] = 255;
        }

        var nm = tree.Renderer.CreateTexture(w, h, pixels).Value;
        Console.WriteLine($"[KernelEngine] NormalMap: handle={nm.Value} width={w} height={h}");

        var matPlain  = tree.Renderer.CreateMaterial(Vector4.One, roughness: 0.3f).Value;
        var matNormal = tree.Renderer.CreateMaterial(Vector4.One, roughness: 0.3f, normalMapHandle: nm).Value;

        tree.AddNode(
            new DirectionalLight { Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)), Intensity = 2f },
            "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 3f) };

        var left = tree.AddNode(new MeshRenderer { MaterialHandle = matPlain }, "PlainQuad");
        left.LocalTransform = left.LocalTransform with { Position = new Vector3(-1.2f, 0f, 0f) };

        var right = tree.AddNode(new MeshRenderer { MaterialHandle = matNormal }, "NormalQuad");
        right.LocalTransform = right.LocalTransform with { Position = new Vector3(1.2f, 0f, 0f) };
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[04_normal_map] Loop running. Close the window to exit.");

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

Console.WriteLine("[04_normal_map] Exited cleanly.");
