using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel().AddNativeFramework()
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
    var cam = app.Tree.AddNode(
        new Camera { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 5f, 15f) };

    // Materials
    var floorMat = resources.CreateMaterial(new Vector4(0.3f, 0.3f, 0.3f, 1f), metallic: 0.0f, roughness: 0.8f);
    var cubeMat = resources.CreateMaterial(new Vector4(0.8f, 0.8f, 0.8f, 1f), metallic: 0.1f, roughness: 0.5f);

    // Floor — the default mesh is a quad in the XY plane (normal +Z), so rotate -90° about X
    // to lay it flat in the XZ plane with its normal pointing up. Scale X/Y (Y becomes depth Z
    // after the rotation); the quad has no thickness so the old (20, 0.1, 20) made a thin strip.
    var floor = app.Tree.AddNode(new MeshRenderer { MaterialHandle = floorMat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with
    {
        Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitX, -MathF.PI / 2f),
        Scale = new Vector3(30f, 30f, 1f),
        Position = new Vector3(0f, 0f, 0f)
    };

    // Grid of cubes
    for (int x = -4; x <= 4; x += 4)
    {
        for (int z = -4; z <= 4; z += 4)
        {
            var n = app.Tree.AddNode(new MeshRenderer { MaterialHandle = cubeMat }, $"Cube_{x}_{z}");
            n.LocalTransform = n.LocalTransform with { Position = new Vector3(x, 1f, z) };
        }
    }

    // Spot lights
    app.Tree.AddNode(
        new RotatingSpotLightNode { 
            Color = new Vector3(1, 0, 0),
            Intensity = 25.0f,
            Range = 60f,
            Offset = 0f
        },
        "Spot_Red");

    app.Tree.AddNode(
        new RotatingSpotLightNode { 
            Color = new Vector3(0, 1, 0),
            Intensity = 25.0f,
            Range = 60f,
            Offset = MathF.PI * 2f / 3f
        },
        "Spot_Green");

    app.Tree.AddNode(
        new RotatingSpotLightNode { 
            Color = new Vector3(0, 0, 1),
            Intensity = 25.0f,
            Range = 60f,
            Offset = MathF.PI * 4f / 3f
        },
        "Spot_Blue");
    return Task.CompletedTask;
};

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.01f, 0.01f, 0.01f, 1f);
    tree.SetAmbientLight(0.01f, 0.01f, 0.01f);
};

app.Run(services);

// ── Rotating spot light ───────────────────────────────────────────────────────

sealed class RotatingSpotLightNode : SpotLight
{
    public float Offset { get; init; } = 0.0f;

    private float _time;

    protected override void Update(float dt)
    {
        _time += dt;
        float x = MathF.Cos(_time + Offset) * 8.0f;
        float z = MathF.Sin(_time + Offset) * 8.0f;
        LocalTransform = LocalTransform with { Position = new Vector3(x, 10.0f, z) };
        Direction = Vector3.Normalize(-LocalTransform.Position);
    }
}
