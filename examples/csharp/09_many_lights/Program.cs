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
    .AddGlfwWindow(1280, 720, "KernelEngine — 09 Many Lights Stress Test")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

int lightCount = 200;

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 09_many_lights");
    Console.WriteLine($"[KernelEngine] Features: {lightCount} point_lights, clustered_lighting");

    // Camera
    var cam = app.Tree.AddNode(
        new Camera { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 30f) };

    // Materials
    var mat = resources.CreateMaterial(new Vector4(1f, 1f, 1f, 1f), metallic: 0.1f, roughness: 0.5f);

    // Wall of cubes
    for (int x = -15; x <= 15; x += 3)
    {
        for (int y = -15; y <= 15; y += 3)
        {
            var n = app.Tree.AddNode(new MeshRenderer { MaterialHandle = mat }, $"Cube_{x}_{y}");
            n.LocalTransform = n.LocalTransform with { Position = new Vector3(x, y, 0f) };
        }
    }

    // Random moving point lights
    var rand = new Random(42);
    for (int i = 0; i < lightCount; i++)
    {
        app.Tree.AddNode(
            new RandomMovingLightNode { 
                Color = new Vector3((float)rand.NextDouble(), (float)rand.NextDouble(), (float)rand.NextDouble()), 
                Intensity = 2.0f + (float)rand.NextDouble() * 3.0f,
                Speed = 0.5f + (float)rand.NextDouble() * 2.0f,
                Radius = 5.0f + (float)rand.NextDouble() * 10.0f
            },
            $"Light_{i}");
    }
    return Task.CompletedTask;
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.01f, 0.01f, 0.01f, 1f);
    tree.SetAmbientLight(0.01f, 0.01f, 0.01f);

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Lights: {lightCount}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);

// ── Random moving point light ──────────────────────────────────────────────────

sealed class RandomMovingLightNode : PointLight
{
    public float Speed { get; init; } = 1.0f;

    private float _time;
    private Vector3 _seed;

    protected override void Start()
    {
        base.Start();
        var rand = new Random(GetHashCode());
        _seed = new Vector3((float)rand.NextDouble() * 100f, (float)rand.NextDouble() * 100f, (float)rand.NextDouble() * 100f);
    }

    protected override void Update(float dt)
    {
        _time += dt * Speed;
        float x = MathF.Sin(_time + _seed.X) * 15.0f;
        float y = MathF.Cos(_time + _seed.Y) * 15.0f;
        float z = MathF.Sin(_time * 0.7f + _seed.Z) * 5.0f + 5.0f;
        LocalTransform = LocalTransform with { Position = new Vector3(x, y, z) };
    }
}
