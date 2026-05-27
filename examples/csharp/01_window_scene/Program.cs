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
    .AddGlfwWindow(1280, 720, "KernelEngine — 01 Window/Tree")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = (resources) =>
{
    // Directional light coming from upper-right-front
    app.Tree.AddNode(
        new DirectionalLight
        {
            Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)),
            Color     = Vector3.One,
            Intensity = 2f,
        },
        "Sun");

    // Camera positioned 5 units back, looking forward along -Z
    var cam = app.Tree.AddNode(
        new Camera { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new Vector3(0f, 0f, 5f),
    };

    var orangeMat = resources.CreateMaterial(new Vector4(1f, 0.5f, 0f, 1f));

    var spinner = app.Tree.AddNode(new SpinnerNode(), "Spinner");
    app.Tree.AddNode(
        new MeshRenderer { MaterialHandle = orangeMat },
        "Quad",
        parent: spinner);
    return Task.CompletedTask;
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;
app.OnUpdate = (tree, input) =>
{
    tree.SetTonemapping(true, exposure: 1.0f, gamma: 2.2f);
    tree.ClearColor(0.15f, 0.15f, 0.15f, 1f);

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[Example 01] FPS: {fps:F2}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);

// ── Scripted spinner node ──────────────────────────────────────────────────────

sealed class SpinnerNode : Node
{
    private float _angle;

    protected override void Update(float dt)
    {
        _angle += 90f * dt;
        if (_angle >= 360f) _angle -= 360f;

        LocalTransform = LocalTransform with
        {
            Rotation = Quaternion.CreateFromYawPitchRoll(_angle * MathF.PI / 180f, 0f, 0f),
        };
    }
}
