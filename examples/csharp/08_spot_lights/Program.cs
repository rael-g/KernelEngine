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
    .AddGlfwWindow(1280, 720, "KernelEngine — 08 Spot Lights")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 08_spot_lights");
    Console.WriteLine("[KernelEngine] Features: spot_lights, clustered_lighting");

    // Camera
    var cam = app.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 5f, 15f) };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Materials
    var floorMat = resources.CreateMaterial(new Vector4(0.3f, 0.3f, 0.3f, 1f), metallic: 0.0f, roughness: 0.8f);
    var cubeMat = resources.CreateMaterial(new Vector4(0.8f, 0.8f, 0.8f, 1f), metallic: 0.1f, roughness: 0.5f);

    // Floor
    var floor = app.Scene.AddNode(new MeshNode { MaterialHandle = floorMat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with 
    { 
        Scale = new Vector3(20f, 0.1f, 20f),
        Position = new Vector3(0f, -0.05f, 0f) 
    };

    // Grid of cubes
    for (int x = -4; x <= 4; x += 4)
    {
        for (int z = -4; z <= 4; z += 4)
        {
            var n = app.Scene.AddNode(new MeshNode { MaterialHandle = cubeMat }, $"Cube_{x}_{z}");
            n.LocalTransform = n.LocalTransform with { Position = new Vector3(x, 1f, z) };
        }
    }

    // Spot lights
    app.Scene.AddNode(
        new RotatingSpotLightNode { 
            Color = new Vector3(1, 0, 0), 
            Intensity = 10.0f,
            Offset = 0f
        },
        "Spot_Red");

    app.Scene.AddNode(
        new RotatingSpotLightNode { 
            Color = new Vector3(0, 1, 0), 
            Intensity = 10.0f,
            Offset = MathF.PI * 2f / 3f
        },
        "Spot_Green");

    app.Scene.AddNode(
        new RotatingSpotLightNode { 
            Color = new Vector3(0, 0, 1), 
            Intensity = 10.0f,
            Offset = MathF.PI * 4f / 3f
        },
        "Spot_Blue");
};

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.01f, 0.01f, 0.01f, 1f);
    scene.SetAmbientLight(0.01f, 0.01f, 0.01f);
};

app.Run(services);

// ── Rotating spot light ───────────────────────────────────────────────────────

sealed class RotatingSpotLightNode : Node
{
    public Vector3 Color     { get; init; } = Vector3.One;
    public float   Intensity { get; init; } = 10.0f;
    public float   Offset    { get; init; } = 0.0f;

    private float _time;

    protected override void OnStart()
    {
        if (SpotLightNode.ComponentId == uint.MaxValue) return;
        ref var comp = ref AddComponent<SpotLightComponent>(SpotLightNode.ComponentId);
        comp = new SpotLightComponent { 
            R = Color.X, G = Color.Y, B = Color.Z,
            Intensity = Intensity,
            Range = 20.0f,
            InnerAngle = 15f,
            OuterAngle = 30f
        };
    }

    protected override unsafe void OnUpdate(float dt)
    {
        _time += dt;
        float x = MathF.Cos(_time + Offset) * 8.0f;
        float z = MathF.Sin(_time + Offset) * 8.0f;
        
        LocalTransform = LocalTransform with { Position = new Vector3(x, 10.0f, z) };

        // Point towards center
        var lookDir = Vector3.Normalize(new Vector3(0, 0, 0) - LocalTransform.Position);
        
        var comp = GetComponent<SpotLightComponent>(SpotLightNode.ComponentId);
        comp->DirX = lookDir.X;
        comp->DirY = lookDir.Y;
        comp->DirZ = lookDir.Z;
    }
}
