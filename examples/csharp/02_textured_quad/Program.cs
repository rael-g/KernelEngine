using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework.Legacy;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel().AddNativeFramework()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 02 Textured Quad")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

int entityCount = 0;

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 02_textured_quad");
    Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
    Console.WriteLine("[KernelEngine] Features: procedural_texture, albedo_material, uv_mapping");

    // Generate checkerboard texture (128x128, 16 px squares)
    const uint width  = 128;
    const uint height = 128;
    byte[] pixels = new byte[width * height * 4];
    for (int y = 0; y < height; y++)
    for (int x = 0; x < width;  x++)
    {
        bool white = ((x / 16) + (y / 16)) % 2 == 0;
        byte v = (byte)(white ? 255 : 64);
        int  i = (y * (int)width + x) * 4;
        pixels[i]     = v;
        pixels[i + 1] = v;
        pixels[i + 2] = v;
        pixels[i + 3] = 255;
    }

    var texHandle = resources.CreateTexture(width, height, pixels);
    Console.WriteLine($"[KernelEngine] Texture: handle={texHandle} width={width} height={height}");

    var matHandle = resources.CreateMaterial(new Vector4(1f, 1f, 1f, 1f), albedo: texHandle);

    app.Tree.AddNode(
        new DirectionalLight
        {
            Direction = Vector3.Normalize(new(0.2f, 1f, 0.5f)),
            Color     = Vector3.One,
            Intensity = 1f,
        },
        "Sun");
    entityCount++;

    var cam = app.Tree.AddNode(
        new Camera { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new Vector3(0f, 0f, 3f),
    };
    entityCount++;

    app.Tree.AddNode(
        new MeshRenderer { MaterialHandle = matHandle },
        "Quad");
    entityCount++;
    return Task.CompletedTask;
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
