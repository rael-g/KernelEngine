using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using KernelEngine.Asset.Assimp;
using KernelEngine.TaskScheduler.Enki;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 12 Asset Loading")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddEnkiTaskScheduler()
    .AddAssimpAssetLoader();

using var app = new Application();

app.OnReady = async (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 12_asset_loading");
    Console.WriteLine("[KernelEngine] Features: assimp_loader, model_to_scene");

    // Camera
    var cam = app.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 2f, 5f) };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Lights
    app.Scene.AddNode(
        new LightNode { Color = Vector3.One, Intensity = 3.0f },
        "Sun").LocalTransform = new Transform { Position = new Vector3(5f, 10f, 5f) };

    // One-line load + add via the Assets façade (cache + dedup) and scene.Add() (uploads textures
    // / materials / meshes + creates MeshNodes per sub-mesh under a root). Replaces the previous
    // 3-step manual loop. Zero raw handles in game code.
    try {
        string modelPath = Path.Combine(AppContext.BaseDirectory, "../../../../../../assets/Box.gltf");
        Console.WriteLine($"[KernelEngine] Loading model: {modelPath}");
        var model = await app.Assets!.LoadModelAsync(modelPath);
        Console.WriteLine($"[KernelEngine] Model loaded: {model.Meshes.Count} sub-meshes");
        app.Scene.Add(model, name: "Box");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[KernelEngine] ERROR loading model: {ex.Message}");
    }
};

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.1f, 0.1f, 0.15f, 1f);
    scene.SetAmbientLight(0.05f, 0.05f, 0.05f);
};

app.Run(services);
