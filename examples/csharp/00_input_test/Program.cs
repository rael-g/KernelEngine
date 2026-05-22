using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// ── 00 Input Test ─────────────────────────────────────────────────────────────
// Press keys and watch the console output.
// WASD, arrow keys, Space, Shift, Ctrl, Escape — all reported here.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddGlfwWindow(640, 120, "KernelEngine — 00 Input Test (press keys, watch console)")
    .AddBgfxRenderer(System.IO.Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

// Keys to monitor — typed Key enum (no magic keycodes).
var watchKeys = new (string Name, Key Key)[]
{
    ("W", Key.W),       ("A", Key.A),         ("S", Key.S),           ("D", Key.D),
    ("Up", Key.Up),     ("Down", Key.Down),   ("Left", Key.Left),     ("Right", Key.Right),
    ("Space", Key.Space), ("Shift", Key.ShiftLeft), ("Ctrl", Key.ControlLeft), ("Escape", Key.Escape),
};

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.1f, 0.1f, 0.1f, 1f);

    var pressed  = new System.Text.StringBuilder();
    var released = new System.Text.StringBuilder();
    var held     = new System.Text.StringBuilder();

    foreach (var (name, key) in watchKeys)
    {
        if (input.IsKeyPressed(key))  pressed.Append($" [{name}]");
        if (input.IsKeyReleased(key)) released.Append($" [{name}]");
        if (input.IsKeyDown(key))     held.Append($" {name}");
    }

    if (pressed.Length  > 0) Console.WriteLine($"PRESSED: {pressed}");
    if (released.Length > 0) Console.WriteLine($"RELEASED:{released}");
    if (held.Length     > 0) Console.Write($"\rHELD:    {held,-40}");
};

app.Run(services);
