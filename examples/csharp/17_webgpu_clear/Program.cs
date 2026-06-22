using KernelEngine.Ecs.Flecs;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;

// Render v2 (webgpu) in the application pipeline: same runtime + module host as
// 01_runtime_clear_color, but the render path is the v2 WebgpuRenderModule —
// device + render core in Zig, passes registered as KE_PHASE_RENDER systems.
// The host only ticks the runtime; no render calls in the loop.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1024, 640, "KernelEngine — 17 Webgpu Clear (v2)"))
    .Add<IRuntimeModule>(new WebgpuRenderModule());

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[17_webgpu_clear] Loop running. Close the window to exit.");

var sw = System.Diagnostics.Stopwatch.StartNew();
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

Console.WriteLine("[17_webgpu_clear] Exited cleanly.");
