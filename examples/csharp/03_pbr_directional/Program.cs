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
    .AddGlfwWindow(800, 600, "Example 03 — PBR Directional")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = () =>
{
    Console.WriteLine("[Example] 03_pbr_directional — 3 materials: dielectric/metal/mixed");

    // ── Lights ──────────────────────────────────────────────────────────────

    // Directional light (0.5, 1.0, 0.3), white, intensity 2.0
    app.ActiveWorld.Scene.AddNode(
        new LightNode
        {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1.0f, 0.3f)),
            Color     = Vector3.One,
            Intensity = 2.0f,
        },
        "Sun");

    // ── Camera ──────────────────────────────────────────────────────────────

    // Camera at Z=5, Y=1, looking at origin
    var cam = app.ActiveWorld.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new Vector3(0f, 1.0f, 5.0f),
    };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // ── Materials ───────────────────────────────────────────────────────────

    // Material 1: metallic=0.0, roughness=0.8 (dielectric rugoso)
    var mat1 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 0.0f, roughness: 0.8f).Value;

    // Material 2: metallic=1.0, roughness=0.1 (metal espelhado)
    var mat2 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 1.0f, roughness: 0.1f).Value;

    // Material 3: metallic=0.5, roughness=0.5 (intermediário)
    var mat3 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 0.5f, roughness: 0.5f).Value;

    // ── Meshes ──────────────────────────────────────────────────────────────

    // Create shared mesh for the quads
    var quadMesh = app.Renderer.CreateMesh(MeshGeometry.QuadVertices, MeshGeometry.QuadIndices).Value;

    // Quad 1 (Left)
    var node1 = app.ActiveWorld.Scene.AddNode(
        new MeshNode { MeshHandle = quadMesh, MaterialHandle = mat1 },
        "QuadDielectric");
    node1.LocalTransform = node1.LocalTransform with { Position = new Vector3(-2.0f, 0f, 0f) };

    // Quad 2 (Center)
    var node2 = app.ActiveWorld.Scene.AddNode(
        new MeshNode { MeshHandle = quadMesh, MaterialHandle = mat2 },
        "QuadMetal");
    node2.LocalTransform = node2.LocalTransform with { Position = new Vector3(0f, 0f, 0f) };

    // Quad 3 (Right)
    var node3 = app.ActiveWorld.Scene.AddNode(
        new MeshNode { MeshHandle = quadMesh, MaterialHandle = mat3 },
        "QuadMixed");
    node3.LocalTransform = node3.LocalTransform with { Position = new Vector3(2.0f, 0f, 0f) };
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
