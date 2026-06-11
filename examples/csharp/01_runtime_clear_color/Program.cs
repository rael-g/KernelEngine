using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// R3-mini: window with a clear color, end-to-end via the runtime + module
// pattern. No Application.cs. No Tree, no nodes, no scene. Just two modules
// (window + renderer) that hand the runtime everything it needs.

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
        clearColor: (0.15f, 0.20f, 0.35f, 1.0f)));   // dark blue

using var sp = services.BuildServiceProvider();

// Single-threaded R3-mini: the host thread doubles as ke.render so bgfx's
// thread-affinity check during Initialize() / ClearColor() / Frame() passes.
// A proper multi-threaded setup (R4) dedicates a render thread + introduces a
// "host-thread phase" in the runtime so render systems run there automatically.
KernelEngine.Kernel.KernelThread.SetCurrentName("ke.render");

var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();
var renderer = sp.GetRequiredService<IRenderer>();

runtime.LoadModules(sp);

Console.WriteLine("[01_runtime_clear_color] Loop running. Close the window to exit.");

var sw = System.Diagnostics.Stopwatch.StartNew();
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;

    // Render calls live on the host thread until R4. The module-registered
    // Initialize already ran during LoadModules.
    renderer.ClearColor(0.15f, 0.20f, 0.35f, 1.0f);
    renderer.Frame();
}

Console.WriteLine("[01_runtime_clear_color] Exited cleanly.");
