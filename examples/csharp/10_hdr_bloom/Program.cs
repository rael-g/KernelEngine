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
    .AddGlfwWindow(1280, 720, "KernelEngine — 10 HDR & Bloom")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 10_hdr_bloom");
    Console.WriteLine("[KernelEngine] Features: hdr_rendering, bloom, tonemapping");

    // Camera
    var cam = app.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 10f) };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Materials
    var mat = resources.CreateMaterial(new Vector4(1f, 1f, 1f, 1f), metallic: 0.1f, roughness: 0.5f);

    // Glowing cube
    var glowingCube = app.Scene.AddNode(new MeshNode { MaterialHandle = mat }, "GlowCube");
    glowingCube.LocalTransform = glowingCube.LocalTransform with { Scale = new Vector3(2f, 2f, 2f) };

    // Very intense light to trigger bloom. Direction must point toward the camera-facing quad
    // (normal +Z), otherwise N·L = 0 and the "glow" cube stays black. Direction is the vector
    // toward the light source, so +Z lights the front face.
    var light = app.Scene.AddNode(
        new LightNode { Direction = new Vector3(0f, 0f, 1f), Color = new Vector3(1f, 0.5f, 0.2f), Intensity = 50.0f },
        "BrightSun");
};

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.01f, 0.01f, 0.01f, 1f);
    
    // Enable Post-FX
    scene.SetTonemapping(true, exposure: 1.0f, gamma: 2.2f);
    scene.SetBloom(true, threshold: 0.8f, intensity: 1.5f);
};

app.Run(services);
