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
    .AddMessagePipe()
    .AddGlfwWindow(1280, 720, "KernelEngine — 02 Textured Quad")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = () =>
{
    app.Renderer.SetTonemapping(true, exposure: 1.0f, gamma: 2.2f);

    // Generate checkerboard texture (128x128, 16px squares)
    uint width = 128;
    uint height = 128;
    byte[] pixels = new byte[width * height * 4];
    for (int y = 0; y < height; y++)
    {
        for (int x = 0; x < width; x++)
        {
            bool white = ((x / 16) + (y / 16)) % 2 == 0;
            byte val = (byte)(white ? 255 : 0);
            int idx = (y * (int)width + x) * 4;
            pixels[idx + 0] = val; // R
            pixels[idx + 1] = val; // G
            pixels[idx + 2] = val; // B
            pixels[idx + 3] = 255; // A
        }
    }

    var texRes = app.Renderer.CreateTexture(width, height, pixels);
    KernelException.ThrowIfFailed(texRes.Code, nameof(app.Renderer.CreateTexture));
    uint texHandle = texRes.Value;

    // Create material with checkerboard texture
    var matRes = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, textureHandle: texHandle);
    KernelException.ThrowIfFailed(matRes.Code, nameof(app.Renderer.CreateMaterial));
    uint matHandle = matRes.Value;

    // Directional light from top-front
    app.ActiveWorld.Scene.AddNode(
        new LightNode
        {
            Direction = Vector3.Normalize(new(0.2f, 1f, 0.5f)),
            Color     = Vector3.One,
            Intensity = 1f,
        },
        "Sun");

    // Camera at Z=3, looking at origin
    var cam = app.ActiveWorld.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new Vector3(0f, 0f, 3f),
    };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Rendered quad
    app.ActiveWorld.Scene.AddNode(
        new MeshNode { MaterialHandle = matHandle },
        "Quad");
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = () =>
{
    // Background padrão (0.05, 0.05, 0.05, 1.0)
    var res = app.Renderer.ClearColor(0.05f, 0.05f, 0.05f, 1f);
    KernelException.ThrowIfFailed(res, nameof(app.Renderer.ClearColor));

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[Example 02] FPS: {fps:F2}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);
