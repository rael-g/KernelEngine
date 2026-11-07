using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Io.Pool;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

var services = new ServiceCollection()
    .AddLogging(logging => logging.AddConsole())
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .Add<IRuntime, Runtime>()
    .AddConfig(new GlfwWindowConfig { Title = "KernelEngine — 17 Webgpu Clear (v2)", Width = 1024, Height = 640 })
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .AddConfig(new DefaultRenderServiceConfig { ShaderDir = ExamplePaths.ShaderDir })
    .Add<IRuntimeModule>(new WebgpuRenderModule());

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[17_webgpu_clear] Loop running. Close the window to exit.");

var sw = System.Diagnostics.Stopwatch.StartNew();
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    window.PollEvents();
    runtime.Tick((float)(now - prev));
    prev = now;
}
runtime.UnloadModules();

Console.WriteLine("[17_webgpu_clear] Exited cleanly.");
