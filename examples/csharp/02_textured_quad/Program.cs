using System.Numerics;
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
    .AddGlfwWindow(800, 600, "Example 02 — Textured Quad")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = () =>
{
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
    uint texHandle = texRes.Value;
    Console.WriteLine($"[Example] 02_textured_quad — texture: {width}x{height} checkerboard, handle: {texHandle}");

    // Create material with checkerboard texture
    var matHandle = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, textureHandle: texHandle).Value;

    // Directional light from top
    app.ActiveWorld.Scene.AddNode(
        new LightNode
        {
            Direction = new Vector3(0f, 1f, 0f),
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

DateTime lastFpsLog = DateTime.Now;
int frameCount = 0;

app.OnUpdate = () =>
{
    _ = app.Renderer.ClearColor(0.1f, 0.1f, 0.1f, 1f);

    frameCount++;
    if ((DateTime.Now - lastFpsLog).TotalSeconds >= 5.0)
    {
        double fps = frameCount / (DateTime.Now - lastFpsLog).TotalSeconds;
        Console.WriteLine($"[Example] FPS: {fps:F2}");
        lastFpsLog = DateTime.Now;
        frameCount = 0;
    }
};

app.Run(services);
