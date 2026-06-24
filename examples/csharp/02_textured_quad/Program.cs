using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;
using KernelEngine.Render;

// 02_textured_quad — procedural checkerboard texture on the built-in quad, lit
// by one directional light. Render v2 (webgpu): a glTF-style material (white
// base-color factor × albedo texture) referenced by the mesh; the forward pass
// samples it. No IRenderer, no contributors.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 02 Textured Quad"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();

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
        var tex = resources.UploadTexture(width, height, pixels);
        var mat = resources.CreateMaterial(Vector4.One, tex);

        tree.AddNode(new DirectionalLight
        {
            Direction = new(0.2f, 1f, 0.5f),
            Color     = Vector3.One,
            Intensity = 1f,
            Ambient   = new(0.2f, 0.2f, 0.2f),
        }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 3f) };

        var quad = KernelEngine.Render.MeshPrimitives.Quad(resources);
        tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mat }, "Quad");
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

runtime.UnloadModules(sp);

Console.WriteLine("[02_textured_quad] Exited cleanly.");
