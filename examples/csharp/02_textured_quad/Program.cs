using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// R6 migration: 02_textured_quad — procedural checkerboard texture on the
// built-in quad, lit by one directional + ambient light. Uses runtime + new
// framework modules end-to-end. No Application.cs.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 02 Textured Quad"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new CameraModule { Position = new(0, 0, 3) })
    .Add<IRuntimeModule>(new LightModule
    {
        Direction = new(0.2f, 1f, 0.5f),
        Color     = Vector3.One,
        Intensity = 1f,
        Ambient   = new(0.2f, 0.2f, 0.2f),
    })
    .Add<IRuntimeModule>(new StaticMeshModule(renderer =>
    {
        // Procedural 128×128 checkerboard, 16-pixel squares.
        const uint width  = 128;
        const uint height = 128;
        var pixels = new byte[width * height * 4];
        for (int y = 0; y < height; y++)
        for (int x = 0; x < width;  x++)
        {
            bool white = ((x / 16) + (y / 16)) % 2 == 0;
            byte v = (byte)(white ? 255 : 64);
            int  i = (y * (int)width + x) * 4;
            pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255;
        }

        var tex = renderer.CreateTexture(width, height, pixels).Value;
        var mat = renderer.CreateMaterial(Vector4.One, textureHandle: tex).Value;
        return (Mesh: default, Material: mat);  // default mesh handle = built-in quad
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[02_textured_quad] Loop running. Close the window to exit.");

var sw = System.Diagnostics.Stopwatch.StartNew();
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

Console.WriteLine("[02_textured_quad] Exited cleanly.");
