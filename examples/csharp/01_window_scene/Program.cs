using System.Numerics;
using KernelEngine;
using KernelEngine.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddMessagePipe()
    .AddGlfwWindow(800, 600, "KernelEngine — C# Window/Scene")
    .AddBgfxRenderer("src/cpp/render/bgfx/shaders");

float hue = 0f;

using var app = new Application();

app.OnReady = () =>
{
    // Directional light coming from upper-right-front
    app.ActiveWorld.Scene.AddNode(
        new LightNode
        {
            Direction = System.Numerics.Vector3.Normalize(new(0.5f, 1f, 0.5f)),
            Color     = System.Numerics.Vector3.One,
            Intensity = 1f,
        },
        "Sun");

    // Camera positioned 5 units back, looking forward along -Z
    var cam = app.ActiveWorld.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new System.Numerics.Vector3(0f, 0f, 5f),
    };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    var orangeMat = app.Renderer.CreateMaterial(1f, 0.5f, 0f, 1f);

    var spinner = app.ActiveWorld.Scene.AddNode(new SpinnerNode(), "Spinner");
    app.ActiveWorld.Scene.AddNode(
        new MeshNode { MaterialHandle = orangeMat },
        "Quad",
        parent: spinner);
};

app.OnUpdate = () =>
{
    hue += 0.003f;
    if (hue > 1f) hue -= 1f;

    float r = MathF.Abs(hue * 6f - 3f) - 1f;
    float g = 2f - MathF.Abs(hue * 6f - 2f);
    float b = 2f - MathF.Abs(hue * 6f - 4f);
    app.Renderer.ClearColor(Math.Clamp(r, 0, 1), Math.Clamp(g, 0, 1), Math.Clamp(b, 0, 1), 1f);
};

app.Run(services);

// ── Scripted spinner node ──────────────────────────────────────────────────────

sealed class SpinnerNode : Node
{
    private float _angle;

    protected override void OnStart()
    {
        Console.WriteLine("[SpinnerNode] started.");
    }

    protected override void OnUpdate(float dt)
    {
        _angle += 90f * dt;
        if (_angle >= 360f) _angle -= 360f;

        LocalTransform = LocalTransform with
        {
            Rotation = System.Numerics.Quaternion.CreateFromYawPitchRoll(
                _angle * MathF.PI / 180f, 0f, 0f),
        };
    }
}
