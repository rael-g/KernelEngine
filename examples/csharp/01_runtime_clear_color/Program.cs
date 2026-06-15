using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// R3-mini / R4: window with a clear color, end-to-end via the runtime + module
// pattern. No Application.cs. No Tree, no nodes, no scene. No manual render
// calls in the host — render systems are pinned to a worker the render module
// names "ke.render", scheduler dispatches them every tick.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 01 Runtime Clear Color"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.15f, 0.20f, 0.35f, 1.0f)));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[01_runtime_clear_color] Loop running. Close the window to exit.");

var sw = System.Diagnostics.Stopwatch.StartNew();
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

Console.WriteLine("[01_runtime_clear_color] Exited cleanly.");
