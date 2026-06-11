using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework.Legacy;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel().AddNativeFramework()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 07 Point Lights")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 07_point_lights");
    Console.WriteLine("[KernelEngine] Features: point_lights, clustered_lighting");

    // Camera
    var cam = app.Tree.AddNode(
        new Camera { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 2f, 15f) };

    // Materials
    var mat = resources.CreateMaterial(new Vector4(1f, 1f, 1f, 1f), metallic: 0.1f, roughness: 0.5f);

    // Grid of spheres (or quads) to see lights
    for (int x = -5; x <= 5; x += 2)
    {
        for (int y = -5; y <= 5; y += 2)
        {
            var n = app.Tree.AddNode(new MeshRenderer { MaterialHandle = mat }, $"Sphere_{x}_{y}");
            n.LocalTransform = n.LocalTransform with { Position = new Vector3(x, y, 0f) };
        }
    }

    // Point lights
    var colors = new[] { Vector3.UnitX, Vector3.UnitY, Vector3.UnitZ, new Vector3(1, 1, 0) };
    for (int i = 0; i < 4; i++)
    {
        var light = app.Tree.AddNode(
            new MovingLightNode { 
                Color = colors[i], 
                Intensity = 5.0f,
                Phase = i * (MathF.PI / 2.0f)
            },
            $"PointLight_{i}");
    }
    return Task.CompletedTask;
};

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.02f, 0.02f, 0.02f, 1f);
    tree.SetAmbientLight(0.01f, 0.01f, 0.01f);
};

app.Run(services);

// ── Moving point light ────────────────────────────────────────────────────────

sealed class MovingLightNode : PointLight
{
    public float Phase { get; init; } = 0.0f;

    private float _time;

    protected override void Update(float dt)
    {
        _time += dt;
        float x = MathF.Cos(_time + Phase) * 5.0f;
        float y = MathF.Sin(_time + Phase) * 5.0f;
        float z = MathF.Sin(_time * 0.5f) * 2.0f + 2.0f;
        LocalTransform = LocalTransform with { Position = new Vector3(x, y, z) };
    }
}
