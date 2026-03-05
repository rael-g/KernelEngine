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
    var spinner = app.ActiveWorld.Scene.AddNode(new SpinnerNode(), "Spinner");
    app.ActiveWorld.Scene.AddNode(
        new MeshNode { Color = new Vector4(1f, 0.5f, 0f, 1f) },
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
