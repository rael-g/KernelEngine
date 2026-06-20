using System.Diagnostics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// Uniform Add<> pattern. Infrastructure (allocator/logger/ecs/scheduler/runtime)
// + modules (window/render/etc.) go through one verb. Headless variants drop
// modules they don't need; runtime never knows what's there.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(800, 600, "KernelEngine — 00 Runtime Minimal"));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

// FpsCounter — host-side system registered directly. Demonstrates that any
// caller can talk to the runtime; modules aren't the only way.
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

double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

Console.WriteLine("[00_runtime_minimal] Exited cleanly.");
