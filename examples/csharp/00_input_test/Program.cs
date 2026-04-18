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
    .AddMessagePipe()
    .AddInput()
    .AddGlfwWindow(640, 120, "KernelEngine — 00 Input Test (press keys, watch console)")
    .AddBgfxRenderer(System.IO.Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

// Keys to monitor: name → GLFW keycode
var watchKeys = new (string Name, int Code)[]
{
    ("W",       87),  ("A",      65),  ("S",    83),  ("D",       68),
    ("Up",     265),  ("Down",  264),  ("Left", 263),  ("Right",  262),
    ("Space",   32),  ("Shift", 340),  ("Ctrl", 341),  ("Escape",  256),
};

app.OnUpdate = () =>
{
    app.Renderer.ClearColor(0.1f, 0.1f, 0.1f, 1f);

    var pressed  = new System.Text.StringBuilder();
    var released = new System.Text.StringBuilder();
    var held     = new System.Text.StringBuilder();

    foreach (var (name, code) in watchKeys)
    {
        if (app.Input!.IsKeyPressed(code))  pressed.Append($" [{name}]");
        if (app.Input!.IsKeyReleased(code)) released.Append($" [{name}]");
        if (app.Input!.IsKeyDown(code))     held.Append($" {name}");
    }

    if (pressed.Length  > 0) Console.WriteLine($"PRESSED: {pressed}");
    if (released.Length > 0) Console.WriteLine($"RELEASED:{released}");
    if (held.Length     > 0) Console.Write($"\rHELD:    {held,-40}");
};

app.Run(services);
