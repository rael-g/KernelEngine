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
    .AddGlfwWindow(1280, 720, "KernelEngine — 03 PBR Directional")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = () =>
{
    app.Renderer.SetTonemapping(true, exposure: 1.0f, gamma: 2.2f);

    // ── Lights ──────────────────────────────────────────────────────────────
    app.ActiveWorld.Scene.AddNode(
        new LightNode
        {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1.0f, 0.3f)),
            Color     = Vector3.One,
            Intensity = 2.0f,
        },
        "Sun");

    // ── Camera ──────────────────────────────────────────────────────────────
    var cam = app.ActiveWorld.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new Vector3(0f, 1.0f, 5.0f),
    };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // ── Materials ───────────────────────────────────────────────────────────
    var mat1 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 0.0f, roughness: 0.8f).Value;
    var mat2 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 1.0f, roughness: 0.1f).Value;
    var mat3 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 0.5f, roughness: 0.5f).Value;

    // ── Meshes (handle 0 = built-in unit quad) ──────────────────────────────
    var node1 = app.ActiveWorld.Scene.AddNode(
        new MeshNode { MaterialHandle = mat1 },
        "QuadDielectric");
    node1.LocalTransform = node1.LocalTransform with { Position = new Vector3(-2.0f, 0f, 0f) };

    var node2 = app.ActiveWorld.Scene.AddNode(
        new MeshNode { MaterialHandle = mat2 },
        "QuadMetal");
    node2.LocalTransform = node2.LocalTransform with { Position = new Vector3(0f, 0f, 0f) };

    var node3 = app.ActiveWorld.Scene.AddNode(
        new MeshNode { MaterialHandle = mat3 },
        "QuadMixed");
    node3.LocalTransform = node3.LocalTransform with { Position = new Vector3(2.0f, 0f, 0f) };
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
        Console.WriteLine($"[Example 03] FPS: {fps:F2}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);
