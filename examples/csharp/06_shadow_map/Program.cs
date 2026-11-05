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
    .AddConfig(new GlfwWindowConfig { Title = "KernelEngine — 06 Shadow Map", Width = 1280, Height = 720 })
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new Vector4(0.1f, 0.1f, 0.15f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderService>();
        Console.WriteLine("[KernelEngine] Example: 06_shadow_map");
        Console.WriteLine("[KernelEngine] Features: shadow_map_directional, ortho_light_frustum, animated_sun");

        const string planeMesh = "plane";
        const string cubeMesh = "cube";

        var floorMat = resources.CreateMaterial("floor", new Vector4(0.5f, 0.5f, 0.5f, 1f), roughness: 0.8f);
        var redMat = resources.CreateMaterial("red", new Vector4(0.8f, 0.2f, 0.2f, 1f), metallic: 0.2f, roughness: 0.3f);

        tree.AddNode(new AnimatedSun
        {
            Color = Vector3.One,
            Intensity = 3f,
            Ambient = new(0.15f, 0.15f, 0.15f),
        }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, NearPlane = 0.1f, FarPlane = 1000f }, "Camera");
        cam.Position = new Vector3(0f, 5f, 10f);

        var floor = tree.AddNode(new MeshRenderer { Mesh = planeMesh, MaterialHandle = floorMat }, "Floor");
        floor.Scale = new Vector3(20f, 1f, 20f);

        var caster = tree.AddNode(new MeshRenderer { Mesh = cubeMesh, MaterialHandle = redMat }, "Caster");
        caster.Position = new Vector3(0f, 1f, 0f);
    }));

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[06_shadow_map] Loop running. Close the window to exit.");

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


Console.WriteLine("[06_shadow_map] Exited cleanly.");

sealed class AnimatedSun : DirectionalLight
{
    private float _t;

    protected override bool HasBehavior => true;

    protected override void OnUpdate(in View view)
    {
        _t += view.DeltaTime;
        float a = MathF.Sin(_t * 0.8f);
        Direction = Vector3.Normalize(new Vector3(a * 0.8f, -1.0f, 0.5f));
    }
}
