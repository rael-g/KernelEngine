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
    .AddGlfwWindow(1280, 720, "KernelEngine — 04 Normal Map")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = () =>
{
    // ── Generate Procedural Normal Map (128x128) ────────────────────────────
    uint width = 128;
    uint height = 128;
    byte[] pixels = new byte[width * height * 4];
    for (int y = 0; y < height; y++)
    {
        for (int x = 0; x < width; x++)
        {
            // Calculate normals based on sine waves to create "ripples"
            float nx = MathF.Sin(x / 8.0f * 2.0f * MathF.PI);
            float ny = MathF.Cos(y / 8.0f * 2.0f * MathF.PI);
            float nz = 1.0f;

            // Normalize
            float invLen = 1.0f / MathF.Sqrt(nx * nx + ny * ny + nz * nz);
            nx *= invLen;
            ny *= invLen;
            nz *= invLen;

            // Map from [-1, 1] to [0, 255]
            int idx = (y * (int)width + x) * 4;
            pixels[idx + 0] = (byte)((nx * 0.5f + 0.5f) * 255);
            pixels[idx + 1] = (byte)((ny * 0.5f + 0.5f) * 255);
            pixels[idx + 2] = (byte)((nz * 0.5f + 0.5f) * 255);
            pixels[idx + 3] = 255;
        }
    }

    var texRes = app.Renderer.CreateTexture(width, height, pixels);
    KernelException.ThrowIfFailed(texRes.Code, "Create Normal Map");
    uint normalMapHandle = texRes.Value;

    Console.WriteLine($"[Example] 04_normal_map — normal map handle: {normalMapHandle}, size: 128x128");

    // ── Materials ───────────────────────────────────────────────────────────
    // Left: Plain white
    var matPlain = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, roughness: 0.3f).Value;
    // Right: White with ripples
    var matNormal = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, roughness: 0.3f, normalMapHandle: normalMapHandle).Value;

    // ── Scene ───────────────────────────────────────────────────────────────
    var meshRes = app.Renderer.CreateMesh(MeshGeometry.QuadVertices, MeshGeometry.QuadIndices);
    uint quadMesh = meshRes.Value;

    var leftNode = app.ActiveWorld.Scene.AddNode(new MeshNode { MeshHandle = quadMesh, MaterialHandle = matPlain }, "PlainQuad");
    leftNode.LocalTransform = leftNode.LocalTransform with { Position = new Vector3(-1.2f, 0f, 0f) };

    var rightNode = app.ActiveWorld.Scene.AddNode(new MeshNode { MeshHandle = quadMesh, MaterialHandle = matNormal }, "NormalQuad");
    rightNode.LocalTransform = rightNode.LocalTransform with { Position = new Vector3(1.2f, 0f, 0f) };

    // ── Environment ─────────────────────────────────────────────────────────
    app.ActiveWorld.Scene.AddNode(new LightNode { 
        Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)), 
        Intensity = 1.5f 
    }, "Sun");

    var cam = app.ActiveWorld.Scene.AddNode(new CameraNode { Fov = 60f }, "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 3f) };
    app.ActiveWorld.ActiveCamera = cam.Entity;
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = () =>
{
    var res = app.Renderer.ClearColor(0.05f, 0.05f, 0.05f, 1f);
    KernelException.ThrowIfFailed(res, nameof(app.Renderer.ClearColor));

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[Example] FPS: {fps:F2}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);
