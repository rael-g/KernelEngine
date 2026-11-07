using System.Diagnostics;
using System.Numerics;

using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Io.Pool;
using KernelEngine.Render;
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
    .AddConfig(new GlfwWindowConfig { Title = "KernelEngine — 10 HDR Tonemapping", Width = 1280, Height = 720 })
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .AddConfig(new DefaultRenderServiceConfig { ShaderDir = ExamplePaths.ShaderDir, ClearColor = new Vector4(0.0f, 0.0f, 0.0f, 1.0f) })
    .Add<IRuntimeModule>(new WebgpuRenderModule())
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderService>();
        Console.WriteLine("[KernelEngine] Example: 10_hdr_tonemapping");
        Console.WriteLine("[KernelEngine] Features: hdr_intermediate, aces_tonemapping");

        var cam = tree.AddNode(new Camera { Fov = 55f, NearPlane = 0.1f, FarPlane = 200f }, "Camera");
        cam.Position = new Vector3(0f, 4f, 12f);

        const string sphere = "sphere";
        const string floor = "plane";

        var matGray = resources.CreateMaterial("gray", new Vector4(0.8f, 0.8f, 0.8f, 1f), metallic: 0.0f, roughness: 0.05f);
        var matCopper = resources.CreateMaterial("copper", new Vector4(0.9f, 0.5f, 0.2f, 1f), metallic: 0.9f, roughness: 0.08f);
        var matBlue = resources.CreateMaterial("blue", new Vector4(0.2f, 0.4f, 0.9f, 1f), metallic: 0.0f, roughness: 0.12f);
        var matFloor = resources.CreateMaterial("floor", new Vector4(0.3f, 0.3f, 0.3f, 1f), metallic: 0.0f, roughness: 0.9f);

        var floorNode = tree.AddNode(new MeshRenderer { Mesh = floor, MaterialHandle = matFloor }, "Floor");
        floorNode.Position = new Vector3(0f, -1f, 0f);
        floorNode.Scale = new Vector3(20f, 1f, 20f);

        var s0 = tree.AddNode(new MeshRenderer { Mesh = sphere, MaterialHandle = matGray }, "SphereNear");
        var s1 = tree.AddNode(new MeshRenderer { Mesh = sphere, MaterialHandle = matCopper }, "SphereMid");
        var s2 = tree.AddNode(new MeshRenderer { Mesh = sphere, MaterialHandle = matBlue }, "SphereFar");
        s0.Position = new Vector3(-3f, 0f, 0f);
        s0.Scale = new Vector3(2f);
        s1.Position = new Vector3(0f, 0f, 0f);
        s1.Scale = new Vector3(2f);
        s2.Position = new Vector3(3f, 0f, 0f);
        s2.Scale = new Vector3(2f);

        tree.AddNode(new AmbientLight { Color = new Vector3(0.01f, 0.01f, 0.015f) }, "Ambient");

        var light = tree.AddNode(new PointLight
        {
            Color = new Vector3(1f, 0.92f, 0.80f),
            Intensity = 5f,
            Radius = 20f,
        }, "Lamp");
        light.Position = new Vector3(-3f, 2f, 1.5f);
    }));

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[10_hdr_tonemapping] Loop running. Close the window to exit.");

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


Console.WriteLine("[10_hdr_tonemapping] Exited cleanly.");
