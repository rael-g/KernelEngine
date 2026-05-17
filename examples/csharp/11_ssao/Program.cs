using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 11 SSAO")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 11_ssao");
    Console.WriteLine("[KernelEngine] Features: ssao, gbuffer_prepass");

    // Camera
    var cam = app.ActiveWorld.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(5f, 5f, 5f) };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Materials
    var mat = resources.CreateMaterial(new Vector4(0.7f, 0.7f, 0.7f, 1f), metallic: 0.0f, roughness: 0.5f);

    // Floor
    var floor = app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = mat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(10f, 0.1f, 10f) };

    // Wall of cubes to see occlusion
    for (int x = -3; x <= 3; x += 1)
    {
        for (int y = 1; y <= 4; y += 1)
        {
            var n = app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = mat }, $"Cube_{x}_{y}");
            n.LocalTransform = n.LocalTransform with { 
                Position = new Vector3(x, y, 0f),
                Scale = new Vector3(0.9f, 0.9f, 0.9f)
            };
        }
    }
};

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.2f, 0.2f, 0.2f, 1f);
    scene.SetAmbientLight(0.05f, 0.05f, 0.05f);
    
    // Enable Post-FX
    scene.SetSsao(true, radius: 0.5f, bias: 0.025f, strength: 2.0f);
};

app.Run(services);
