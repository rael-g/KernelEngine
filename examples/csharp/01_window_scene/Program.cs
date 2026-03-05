using System;

using KernelEngine;
using KernelEngine.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Glfw;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

// ── Entry point ───────────────────────────────────────────────────────────────

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddMessagePipe()
    .AddGlfwWindow(800, 600, "KernelEngine — C# Window/Scene")
    .AddBgfxRenderer("src/cpp/render/bgfx/shaders")
    .AddSingleton<ILoggerSink, ConsoleLoggerSink>();

using var app = new WindowSceneApp();
app.Run(services);

// ── App ───────────────────────────────────────────────────────────────────────

sealed class WindowSceneApp : Application
{
    private float _hue;

    protected override void OnReady()
    {
        // Populate the scene before the loop starts.
        var node = ActiveWorld.Scene.CreateNode(new SpinnerNode(), "Spinner", Allocator);
        ActiveWorld.Scene.Root.AddChild(node);
    }

    // The base loop calls World.Update() and Window.PollEvents() each frame.
    // Override to insert per-frame logic (clear color animation, etc.).
    protected override void OnUpdate()
    {
        _hue += 0.003f;
        if (_hue > 1.0f) _hue -= 1.0f;

        // Hue → RGB (simple approximation for the demo).
        float r = MathF.Abs(_hue * 6f - 3f) - 1f;
        float g = 2f - MathF.Abs(_hue * 6f - 2f);
        float b = 2f - MathF.Abs(_hue * 6f - 4f);
        Renderer.ClearColor(Math.Clamp(r, 0, 1), Math.Clamp(g, 0, 1), Math.Clamp(b, 0, 1), 1f);
    }
}

// ── Scripted node ─────────────────────────────────────────────────────────────

sealed class SpinnerNode : Node
{
    private float _angle;

    protected override void OnStart()
    {
        Console.WriteLine("[SpinnerNode] started.");
    }

    protected override void OnUpdate(float dt)
    {
        _angle += 90f * dt; // 90°/s
        if (_angle >= 360f) _angle -= 360f;

        LocalTransform = LocalTransform with
        {
            Rotation = System.Numerics.Quaternion.CreateFromYawPitchRoll(
                _angle * MathF.PI / 180f, 0f, 0f),
        };
    }
}

// ── Console logger sink ───────────────────────────────────────────────────────

sealed class ConsoleLoggerSink : ILoggerSink
{
    public void Log(ke_log_level level, string tag, string message) =>
        Console.WriteLine($"[{level}] {tag}: {message}");
}
