using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using KernelEngine.Asset.Assimp;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 13 Full Scene Demo")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddAssimpAssetLoader();

using var app = new Application();

app.OnReady = async (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 13_full_scene");
    Console.WriteLine("[KernelEngine] Features: all_stabilized_systems, shadows, hdr, bloom, ssao, many_lights, assimp");

    // Camera
    var cam = app.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "MainCamera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(8f, 8f, 15f) };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Static directional light
    var sun = app.Scene.AddNode(
        new LightNode { Color = new Vector3(1f, 0.95f, 0.8f), Intensity = 4.0f },
        "Sun");
    sun.LocalTransform = sun.LocalTransform with { Position = new Vector3(10f, 20f, 10f) };

    // Ground plane
    var floorMat = await resources.CreateMaterialAsync(new Vector4(0.2f, 0.2f, 0.2f, 1f), metallic: 0.0f, roughness: 0.9f);
    var floor = app.Scene.AddNode(new MeshNode { MaterialHandle = floorMat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(50f, 0.1f, 50f) };

    // Load Model
    var loader = app.Services.GetRequiredService<AssetLoader>();
    try {
        string modelPath = Path.Combine(AppContext.BaseDirectory, "../../../../../assets/Box.gltf");
        using var modelData = await loader.LoadModelAsync(modelPath);
        var modelRoot = await modelData.AddToSceneAsync(app.ActiveWorld, resources, "CenterBox");
        modelRoot.LocalTransform = modelRoot.LocalTransform with { 
            Position = new Vector3(0f, 2f, 0f),
            Scale = new Vector3(2.0f) 
        };
    } catch { /* ignore */ }

    // Dynamic point lights
    for (int i = 0; i < 8; i++)
    {
        app.Scene.AddNode(
            new OrbitingLight { 
                Color = i % 2 == 0 ? Vector3.UnitX : Vector3.UnitZ, 
                Radius = 8f,
                Speed = 0.5f + i * 0.1f,
                Phase = i * (MathF.PI / 4f)
            },
            $"OrbitLight_{i}");
    }
};

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.05f, 0.05f, 0.08f, 1f);
    scene.SetAmbientLight(0.02f, 0.02f, 0.02f);
    
    // Enable all post-FX
    scene.SetTonemapping(true, 1.0f, 2.2f);
    scene.SetBloom(true, 0.9f, 1.0f);
    scene.SetSsao(true, 0.5f, 0.025f, 1.5f);
};

app.Run(services);

// ── Helpers ──────────────────────────────────────────────────────────────────

sealed class OrbitingLight : Node
{
    public Vector3 Color { get; init; } = Vector3.One;
    public float Radius { get; init; } = 5f;
    public float Speed { get; init; } = 1.0f;
    public float Phase { get; init; } = 0.0f;
    private float _time;

    protected override void OnStart()
    {
        var comp = AddComponent<PointLightComponent>(PointLightNode.ComponentId);
        comp[0] = new PointLightComponent { R = Color.X, G = Color.Y, B = Color.Z, Intensity = 10f, Radius = 10f };
    }

    protected override void OnUpdate(float dt)
    {
        _time += dt * Speed;
        float x = MathF.Cos(_time + Phase) * Radius;
        float z = MathF.Sin(_time + Phase) * Radius;
        LocalTransform = LocalTransform with { Position = new Vector3(x, 3f, z) };
    }
}
