using System.Diagnostics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Runtime;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// R3-A: minimal proof that IRuntime hosts a real OS window + frame loop.
// No renderer, no scene tree, no resources — just window pump driven by a
// runtime system and timing driven by the host. Open question this answers:
// can a runtime (flecs-backed) coexist with the existing GLFW plugin without
// going through Application.cs? Answer below.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(800, 600, "KernelEngine — 00 Runtime Minimal");

using var sp = services.BuildServiceProvider();
var window    = sp.GetRequiredService<IWindow>();
var allocator = sp.GetRequiredService<Allocator>();

using var ecs     = new FlecsEcs(allocator);
using var runtime = new Runtime(allocator, ecs);

// WindowModule — registers the OS poll in PreUpdate so input + close events
// reach the host before any Update system runs. Wraps the existing GLFW plugin;
// no rewrite needed.
runtime.RegisterModule("Window", rt =>
{
    rt.RegisterSystem("PollEvents", RuntimePhase.PreUpdate, (_, _) =>
    {
        window.PollEvents();
    });
});

// FpsCounter — host-side system registered directly (no module). Demonstrates
// the runtime can drive arbitrary per-frame work; FPS prints to console every
// 1s so the user sees the loop is alive without a renderer.
var sw           = Stopwatch.StartNew();
double lastPrint = 0;
long   ticks     = 0;
runtime.RegisterSystem("FpsCounter", RuntimePhase.Update, (_, _) =>
{
    ticks++;
    double now = sw.Elapsed.TotalSeconds;
    if (now - lastPrint >= 1.0)
    {
        Console.WriteLine($"[00_runtime_minimal] ticks={ticks} ({ticks / (now - lastPrint):F1} Hz)");
        ticks = 0;
        lastPrint = now;
    }
});

Console.WriteLine("[00_runtime_minimal] Loop running. Close the window to exit.");

// Frame loop. The runtime owns its tick; the host owns the dt and the
// while-should-not-close condition. R5+ will move the loop ownership inside
// runtime.Run(cancel_token) once shutdown semantics get fleshed out.
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

Console.WriteLine("[00_runtime_minimal] Exited cleanly.");
