using System.Numerics;
using KernelEngine.Configuration;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel().AddNativeFramework()
    .AddLogger().AddConsoleSink(LogLevel.Info)
    .AddInput()
    .AddProjectConfig()
    .AddGlfwWindow()
    .AddBgfxRenderer();

using var app = new Application();

app.OnUpdate = (tree, _) =>
{
    tree.ClearColor(0.1f, 0.1f, 0.15f, 1f);
    tree.SetAmbientLight(0.15f, 0.15f, 0.15f);
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
