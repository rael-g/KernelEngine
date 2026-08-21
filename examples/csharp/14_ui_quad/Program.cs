using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;
using KernelEngine.Render;
using KernelEngine.Render.Native;
using KernelEngine.Text;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddTextStbTrueType()
    .AddAssetResolver()
    .Add<INativeEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(960, 540, "KernelEngine — 14 UI Quad"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new Vector4(0.10f, 0.12f, 0.16f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 14_ui_quad");
        Console.WriteLine("[KernelEngine] Renderer: webgpu/render-v2");
        Console.WriteLine("[KernelEngine] Features: ui_overlay_pass, labels, stb_truetype");

        var fontPath = ExamplePaths.SystemFont;
        var loader   = sp.GetRequiredService<IFontLoader>();
        var font     = Font.Load(resources, loader, fontPath, pixelSize: 48f);
        Console.WriteLine($"[KernelEngine] Font: {fontPath}, lineHeight={font.LineHeight:F1} ascent={font.Ascent:F1}");

        tree.AddNode(new Label
        {
            Text   = "Top-left, anchor (0,0)",
            Font     = fontPath,
            FontSize = 48f,
            Color  = new Vector4(1f, 0.6f, 0.3f, 1f),
            Anchor = new Vector2(0f, 0f),
            Offset = new Vector2(20, 20),
        }, "TopLeft");

        tree.AddNode(new Label
        {
            Text   = "Top center, anchor (0.5, 0)",
            Font     = fontPath,
            FontSize = 48f,
            Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.5f, 0f),
            Offset = new Vector2(0, 80),
        }, "TopCenter");

        tree.AddNode(new Label
        {
            Text   = "Bottom-right (1,1)",
            Font     = fontPath,
            FontSize = 48f,
            Color  = new Vector4(0.3f, 0.7f, 1f, 1f),
            Anchor = new Vector2(1f, 1f),
            Offset = new Vector2(-20, -20),
        }, "BottomRight");

        tree.AddNode(new BackgroundQuad(), "BackgroundQuad");
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[14_ui_quad] Loop running. Close the window to exit.");

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

sealed class BackgroundQuad : Node
{
    private uint _quadCid;

    protected override void OnBind(NodeWorld nodeWorld) =>
        _quadCid = nodeWorld.RegisterComponent<ke_ui_quad_component>("ui_quad");

    protected override bool HasBehavior => true;

    protected override void OnUpdate(in View view)
    {
        var quad = new ke_ui_quad_component
        {
            texture_bits = TextureHandle.None.Value,
            dst_x = 360, dst_y = 220, dst_w = 240, dst_h = 100,
            u0 = 0, v0 = 0, u1 = 1, v1 = 1,
        };
        quad.color[0] = 0.20f * 0.5f;
        quad.color[1] = 0.85f * 0.5f;
        quad.color[2] = 0.30f * 0.5f;
        quad.color[3] = 0.5f;
        Attach(in view, _quadCid, in quad);
    }
}
