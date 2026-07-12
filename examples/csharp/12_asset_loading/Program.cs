using System.Diagnostics;
using System.Numerics;
using KernelEngine.Asset.Assimp;
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
using KernelEngine.Asset;

// 12_asset_loading — loads assets/Box.gltf via the Assimp plugin and places it
// in a lit scene. Exercises the IRenderResources overload of AddModel so
// textures, materials and meshes flow through the render-v2 upload path.

string modelPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../../assets/Box.gltf"));

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddAssimpAssetLoader()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 12 Asset Loading"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../../build/win/bin/shaders")), clearColor: new Vector4(0.1f, 0.1f, 0.15f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 12_asset_loading");
        Console.WriteLine("[KernelEngine] Renderer: webgpu/render-v2");
        Console.WriteLine("[KernelEngine] Features: assimp_loader, model_to_scene");

        tree.AddNode(new AmbientLight { Color = new(0.05f, 0.05f, 0.05f) }, "Ambient");

        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 2f, 5f) };

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new Vector3(0.3f, -1.0f, -0.5f)),
            Color     = Vector3.One,
            Intensity = 3f,
        }, "Sun");

        Console.WriteLine($"[KernelEngine] Loading model: {modelPath}");
        var loader = sp.GetRequiredService<IAssetLoader>();
        using var model = loader.LoadModel(modelPath);
        Console.WriteLine($"[KernelEngine] Model loaded: {model.Meshes.Count} sub-meshes, {model.Materials.Count} mats, {model.Textures.Count} textures");
        var nodes = tree.AddModel(model, resources, rootName: "Box");
        Console.WriteLine($"[KernelEngine] Added {nodes.Count} mesh nodes to the scene.");
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[12_asset_loading] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[12_asset_loading] Exited cleanly.");
