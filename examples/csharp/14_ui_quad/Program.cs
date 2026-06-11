using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// 14_ui_quad — smoke test for the UI overlay pass. Draws three flat-color
// rectangles in screen-pixel coordinates on top of a cleared frame. Labels
// (text rendering) are deferred to a future migration card — they need Font
// loading + glyph atlas + label render system that haven't been ported yet.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(960, 540, "KernelEngine — 14 UI Quad"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.10f, 0.12f, 0.16f, 1.0f)))
    .Add<IRuntimeModule>(new SceneRenderModule())
    .AddSingleton<IFrameContributor, UiQuadContributor>();

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[14_ui_quad] Loop running. Close the window to exit.");
Console.WriteLine("[KernelEngine] Example: 14_ui_quad");
Console.WriteLine("[KernelEngine] Features: ui_overlay_pass, screen_space_quads (labels deferred)");

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[14_ui_quad] Exited cleanly.");

// ── Three colored UI quads emitted every frame ───────────────────────────────

sealed class UiQuadContributor : IFrameContributor
{
    public void Contribute(IFramePacket packet)
    {
        // Pre-multiplied alpha — colors are RGBA, the alpha column doubles as
        // the overall opacity.
        packet.AddUiQuadCommand(TextureHandle.None,
            dstX:  20, dstY:  20, dstW: 240, dstH: 60,
            u0: 0, v0: 0, u1: 1, v1: 1,
            r: 1f, g: 0.6f, b: 0.3f, a: 1f);

        packet.AddUiQuadCommand(TextureHandle.None,
            dstX: 360, dstY: 220, dstW: 240, dstH: 100,
            u0: 0, v0: 0, u1: 1, v1: 1,
            r: 0.20f * 0.5f, g: 0.85f * 0.5f, b: 0.30f * 0.5f, a: 0.5f);

        packet.AddUiQuadCommand(TextureHandle.None,
            dstX: 720, dstY: 460, dstW: 220, dstH: 60,
            u0: 0, v0: 0, u1: 1, v1: 1,
            r: 0.3f, g: 0.7f, b: 1f, a: 1f);
    }
}
