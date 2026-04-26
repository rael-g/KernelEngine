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

// PBR params logged at startup
const float metal0 = 0.0f; const float rough0 = 0.8f;
const float metal1 = 1.0f; const float rough1 = 0.1f;
const float metal2 = 0.5f; const float rough2 = 0.5f;

int entityCount = 0;

app.OnReady = () =>
{
    Console.WriteLine("[KernelEngine] Example: 03_pbr_directional");
    Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
    Console.WriteLine("[KernelEngine] Features: pbr_ggx, directional_light, orbiting_light");
    Console.WriteLine($"[KernelEngine] PBR materials: " +
        $"dielectric(m={metal0:F1} r={rough0:F1})  " +
        $"metal(m={metal1:F1} r={rough1:F1})  " +
        $"mixed(m={metal2:F1} r={rough2:F1})");

    var light = app.ActiveWorld.Scene.AddNode(
        new OrbitingLightNode { Color = Vector3.One, Intensity = 3.0f },
        "Sun");
    entityCount++;

    var cam = app.ActiveWorld.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new Vector3(0f, 1.0f, 5.0f),
    };
    app.ActiveWorld.ActiveCamera = cam.Entity;
    entityCount++;

    var mat0 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: metal0, roughness: rough0).Value;
    var mat1 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: metal1, roughness: rough1).Value;
    var mat2 = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: metal2, roughness: rough2).Value;

    var n0 = app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = mat0 }, "QuadDielectric");
    n0.LocalTransform = n0.LocalTransform with { Position = new Vector3(-2f, 0f, 0f) };
    entityCount++;

    var n1 = app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = mat1 }, "QuadMetal");
    entityCount++;

    var n2 = app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = mat2 }, "QuadMixed");
    n2.LocalTransform = n2.LocalTransform with { Position = new Vector3(2f, 0f, 0f) };
    entityCount++;
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
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Entities: {entityCount}  Lights: 0p 0s 1d");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);

// ── Orbiting directional light ────────────────────────────────────────────────

sealed class OrbitingLightNode : Node
{
    public Vector3 Color     { get; init; } = Vector3.One;
    public float   Intensity { get; init; } = 3f;

    private float _angle;

    protected override void OnStart()
    {
        if (LightNode.ComponentId == uint.MaxValue) return;
        var dir = CurrentDir();
        ref var comp = ref AddComponent<LightComponent>(LightNode.ComponentId);
        comp = new LightComponent { DirX = dir.X, DirY = dir.Y, DirZ = dir.Z,
                                    R = Color.X, G = Color.Y, B = Color.Z,
                                    Intensity = Intensity };
    }

    protected override unsafe void OnUpdate(float dt)
    {
        _angle += 60f * dt * MathF.PI / 180f;
        var dir = CurrentDir();
        var comp = GetComponent<LightComponent>(LightNode.ComponentId);
        comp->DirX = dir.X;
        comp->DirY = dir.Y;
        comp->DirZ = dir.Z;
    }

    private Vector3 CurrentDir() =>
        Vector3.Normalize(new Vector3(MathF.Sin(_angle), 1f, MathF.Cos(_angle)));
}
