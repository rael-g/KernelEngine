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
    .AddConfig(new GlfwWindowConfig { Title = "KernelEngine — 07 Point Lights", Width = 1280, Height = 720 })
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new Vector4(0.02f, 0.02f, 0.02f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderService>();
        Console.WriteLine("[KernelEngine] Example: 07_point_lights");
        Console.WriteLine("[KernelEngine] Features: point_lights, multi_light_accumulation");

        tree.AddNode(new AmbientLight { Color = new(0.01f, 0.01f, 0.01f) }, "Ambient");

        var cam = tree.AddNode(new Camera { Fov = 60f, NearPlane = 0.1f, FarPlane = 1000f }, "Camera");
        cam.Position = new Vector3(0f, 2f, 15f);

        const string quad = "quad";
        var mat = resources.CreateMaterial("grid_quad", Vector4.One, metallic: 0.1f, roughness: 0.5f);

        for (int x = -5; x <= 5; x += 2)
            for (int y = -5; y <= 5; y += 2)
            {
                var n = tree.AddNode(new MeshRenderer { Mesh = quad, MaterialHandle = mat }, $"Quad_{x}_{y}");
                n.Position = new Vector3(x, y, 0f);
            }

        var colors = new[] { Vector3.UnitX, Vector3.UnitY, Vector3.UnitZ, new Vector3(1f, 1f, 0f) };
        for (int i = 0; i < 4; i++)
        {
            tree.AddNode(new MovingPointLight
            {
                Color = colors[i],
                Intensity = 5f,
                Radius = 15f,
                Phase = i * (MathF.PI / 2f),
            }, $"PointLight_{i}");
        }
    }));

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[07_point_lights] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    window.PollEvents();
    runtime.Tick((float)(now - prev));
    prev = now;
}
runtime.UnloadModules();


Console.WriteLine("[07_point_lights] Exited cleanly.");

sealed class MovingPointLight : PointLight
{
    public float Phase { get; init; }

    private float _time;

    protected override bool HasBehavior => true;

    protected override void OnUpdate(in View view)
    {
        _time += view.DeltaTime;
        float x = MathF.Cos(_time + Phase) * 5f;
        float y = MathF.Sin(_time + Phase) * 5f;
        float z = MathF.Sin(_time * 0.5f) * 2f + 2f;
        Position = new Vector3(x, y, z);
    }
}
