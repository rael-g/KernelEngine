using System.Diagnostics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// Uniform Add<> pattern in action: every infrastructure piece + every module
// goes through the same verb. Headless variants drop modules they don't need;
// the runtime never knows what's present.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(800, 600, "KernelEngine — 00 Runtime Minimal")
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>();
// Future: .Add<IRuntimeModule>(new GlfwWindowModule(...)) once the module ships.
// For this example we still wire window pump as a system inline below.

using var sp     = services.BuildServiceProvider();
var window       = sp.GetRequiredService<IWindow>();
var runtime      = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);  // no modules registered yet → no-op; ready for when they are

// WindowModule — registers the OS poll in PreUpdate. Future-fact: this whole
// block becomes  `.Add<IRuntimeModule>(new GlfwWindowModule(...))`  when the
// module class ships (commit 3 of the R3 saga).
runtime.RegisterModule("Window", rt =>
{
    rt.RegisterSystem("PollEvents", RuntimePhase.PreUpdate, (_, _) =>
    {
        window.PollEvents();
    });
});

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
