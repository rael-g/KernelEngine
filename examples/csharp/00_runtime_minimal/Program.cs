using System.Diagnostics;

using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Io.Pool;
using KernelEngine.Logger;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;

#region compose
var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .Add<IRuntime, Runtime>()
    .AddConfig(new GlfwWindowConfig(Title: "KernelEngine — 00 Runtime Minimal", Width: 800, Height: 600))
    .Add<IRuntimeModule>(new GlfwWindowModule());
#endregion

#region load
using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);
#endregion

var sw = Stopwatch.StartNew();
double lastPrint = 0;
long ticks = 0;
#region system
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
#endregion

Console.WriteLine("[00_runtime_minimal] Loop running. Close the window to exit.");

#region loop
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    window.PollEvents();
    runtime.Tick((float)(now - prev));
    prev = now;
}
runtime.UnloadModules();
#endregion

Console.WriteLine("[00_runtime_minimal] Exited cleanly.");
