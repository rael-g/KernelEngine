using System.Numerics;
using System.Diagnostics;
using KernelEngine.Configuration;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink(LogLevel.Info)
    .AddInput()
    .AddProjectConfig()   // auto-discovers ./Project next to the executable
    .AddGlfwWindow()
    .AddBgfxRenderer();

using var app = new Application();

app.OnReady = async (_) =>
{
    Console.WriteLine("[KernelEngine] Example: 06_shadow_map");
    Console.WriteLine("[KernelEngine] Features: shadow_mapping, directional_light, floor_plane, cube");

    // Scene is fully self-describing: nodes + transforms + resource refs (Mesh/Material via res://).
    await SceneLoader.LoadAsync(app.Tree, "Main.scene", app.Resources);
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.1f, 0.1f, 0.15f, 1f);
    tree.SetAmbientLight(0.15f, 0.15f, 0.15f);

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);

// ── Helpers ──────────────────────────────────────────────────────────────────

/// <summary>
/// Directional light that sweeps its azimuth back and forth over time, so the cube's shadow
/// slides across the floor — a visual check that the shadow projection tracks the light.
/// </summary>
sealed class AnimatedSun : DirectionalLight
{
    private float _t;

    protected override void Update(float dt)
    {
        _t += dt;
        float a = MathF.Sin(_t * 0.8f);                       // -1..1 sweep
        Direction = Vector3.Normalize(new Vector3(a * 0.8f, 1.0f, 0.5f));
    }
}
