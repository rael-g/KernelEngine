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

// 04_normal_map — two quads side by side; the right one carries a procedural
// ripple normal map, the left has the same material without it. Render v2
// (webgpu): tangent-space normal mapping in the forward pass perturbs the PBR
// lighting (watch the specular highlight under the static directional light).

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 04 Normal Map"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new Vector4(0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 04_normal_map");
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
        var nm = resources.UploadTexture("bumps_normal", w, h, pixels);

        var matPlain  = resources.CreateMaterial("plain", Vector4.One, roughness: 0.3f);
        var matNormal = resources.CreateMaterial("normal_mapped", Vector4.One, roughness: 0.3f, normalMap: nm);

        tree.AddNode(
            new DirectionalLight { Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)), Intensity = 2f },
            "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 3f) };

        var quad = KernelEngine.Render.MeshPrimitives.Quad(resources);

        var left = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = matPlain }, "PlainQuad");
        left.LocalTransform = left.LocalTransform with { Position = new Vector3(-1.2f, 0f, 0f) };

        var right = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = matNormal }, "NormalQuad");
        right.LocalTransform = right.LocalTransform with { Position = new Vector3(1.2f, 0f, 0f) };
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[04_normal_map] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[04_normal_map] Exited cleanly.");
