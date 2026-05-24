using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 04 Normal Map")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

int entityCount = 0;

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 04_normal_map");
    Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
    Console.WriteLine("[KernelEngine] Features: normal_map, tbn, tangent_space, pbr_ggx");

    // Procedural ripple normal map (128x128)
    const uint w = 128, h = 128;
    byte[] pixels = new byte[w * h * 4];
    for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++)
    {
        float nx = MathF.Sin(x / 8.0f * 2f * MathF.PI);
        float ny = MathF.Cos(y / 8.0f * 2f * MathF.PI);
        float nz = 1.0f;
        float inv = 1f / MathF.Sqrt(nx*nx + ny*ny + nz*nz);
        nx *= inv; ny *= inv; nz *= inv;
        int i = (y * (int)w + x) * 4;
        pixels[i]     = (byte)((nx * 0.5f + 0.5f) * 255);
        pixels[i + 1] = (byte)((ny * 0.5f + 0.5f) * 255);
        pixels[i + 2] = (byte)((nz * 0.5f + 0.5f) * 255);
        pixels[i + 3] = 255;
    }

    var nmHandle = resources.CreateTexture(w, h, pixels);
    Console.WriteLine($"[KernelEngine] NormalMap: handle={nmHandle} width={w} height={h}");

    var matPlain  = resources.CreateMaterial(Vector4.One, roughness: 0.3f);
    var matNormal = resources.CreateMaterial(Vector4.One, roughness: 0.3f, normalMap: nmHandle);

    var left = app.Tree.AddNode(new MeshRenderer { MaterialHandle = matPlain  }, "PlainQuad");
    left.LocalTransform = left.LocalTransform with { Position = new Vector3(-1.2f, 0f, 0f) };
    entityCount++;

    var right = app.Tree.AddNode(new MeshRenderer { MaterialHandle = matNormal }, "NormalQuad");
    right.LocalTransform = right.LocalTransform with { Position = new Vector3(1.2f, 0f, 0f) };
    entityCount++;

    app.Tree.AddNode(
        new DirectionalLight { Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)), Intensity = 2f },
        "Sun");
    entityCount++;

    var cam = app.Tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 3f) };
    entityCount++;
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.05f, 0.05f, 0.05f, 1f);

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Entities: {entityCount}  Lights: 0p 0s 1d");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);
