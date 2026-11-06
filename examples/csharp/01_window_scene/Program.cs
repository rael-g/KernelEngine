using System.Diagnostics;
using System.Numerics;

using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Io.Pool;
using KernelEngine.Logger;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .Add<IRuntime, Runtime>()
#region modules
    .AddConfig(new GlfwWindowConfig { Title = "KernelEngine — 01 Window/Tree", Width = 1280, Height = 720 })
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .AddConfig(new DefaultRenderServiceConfig { ShaderDir = ExamplePaths.ShaderDir, ClearColor = new Vector4(0.15f, 0.15f, 0.15f, 1.0f) })
    .Add<IRuntimeModule>(new WebgpuRenderModule())
    .Add<IRuntimeModule>(new FrameworkModule())
#endregion
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderService>();
        Console.WriteLine("[KernelEngine] Example: 01_window_scene");
        Console.WriteLine("[KernelEngine] Features: window, renderer, single_quad, spinner_behavior");

        #region scene
        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1f, 0.5f)),
            Color = Vector3.One,
            Intensity = 2f,
        }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, NearPlane = 0.1f, FarPlane = 1000f }, "Camera");
        cam.Position = new Vector3(0f, 0f, 5f);

        const string quad = "quad";
        var orange = resources.CreateMaterial("orange", new Vector4(1f, 0.5f, 0f, 1f));
        tree.AddNode(new SpinningQuad { Mesh = quad, MaterialHandle = orange }, "Spinner");
        #endregion
    }));

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[01_window_scene] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
int frameCount = 0;
double fpsWindowStart = 0;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    window.PollEvents();
    runtime.Tick((float)(now - prev));
    prev = now;

    frameCount++;
    if (now - fpsWindowStart >= 5.0)
    {
        double fps = frameCount / (now - fpsWindowStart);
        Console.WriteLine($"[Example 01] FPS: {fps:F2}");
        frameCount = 0;
        fpsWindowStart = now;
    }
}
runtime.UnloadModules();


Console.WriteLine("[01_window_scene] Exited cleanly.");

#region behavior
sealed partial class SpinningQuad : MeshRenderer
{
    private float _angle;

    void Update(in View view)
    {
        _angle += 90f * view.DeltaTime;
        if (_angle >= 360f) _angle -= 360f;

        Rotation = Quaternion.CreateFromYawPitchRoll(_angle * MathF.PI / 180f, 0f, 0f);
    }
}
#endregion
