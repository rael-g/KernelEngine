using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework.Legacy;
using KernelEngine.Text.StbTrueType;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// ── 14 — UI Quad ──────────────────────────────────────────────────────────────
// Smoke test for the UI overlay render pass (Tier P P1 Stage A). Draws three flat-color
// rectangles in screen-pixel coordinates over an otherwise empty scene to validate:
//   • view 7 setup (ortho 2D pixel space, alpha blend, no depth)
//   • SubmitUiQuad path (kernel API → frame_packet → bgfx → vs/fs_ui_quad shaders)
//   • backbuffer-pixel coordinates land where expected (top-left origin)
//   • alpha blending composes over the cleared frame.
//
// When Label + LabelRenderSystem land (Stage C), this example grows to include text.

var services = new ServiceCollection()
    .AddKernel().AddNativeFramework()
    .AddLogger().AddConsoleSink(LogLevel.Warning)
    .AddGlfwWindow(960, 540, "KernelEngine — 14 UI Quad")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddTextStbTrueType();

using var app = new Application();
Font? font = null;

app.OnReady = async (_) =>
{
    // Load a system font as the smoke source — Windows ships Arial at a well-known path.
    var fontPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), "arial.ttf");
    font = await app.Assets!.LoadFontAsync(fontPath, pixelSize: 48);

    app.Tree.AddNode(new Label {
        Name   = "TopLeft",
        Text   = "Top-left, anchor (0,0)",
        Font   = font,
        Color  = new Vector4(1f, 0.6f, 0.3f, 1f),
        Anchor = new Vector2(0f, 0f),
        Offset = new Vector2(20, 20),
    });
    app.Tree.AddNode(new Label {
        Name   = "TopCenter",
        Text   = "Top center, anchor (0.5, 0)",
        Font   = font,
        Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
        Anchor = new Vector2(0.5f, 0f),
        Offset = new Vector2(0, 80),
    });
    app.Tree.AddNode(new Label {
        Name   = "BottomRight",
        Text   = "Bottom-right (1,1)",
        Font   = font,
        Color  = new Vector4(0.3f, 0.7f, 1f, 1f),
        Anchor = new Vector2(1f, 1f),
        Offset = new Vector2(-20, -20),
    });
};

app.OnUpdate = (writer, _) =>
{
    writer.ClearColor(0.10f, 0.12f, 0.16f, 1f);

    // Plain UI quad backdrop (smoke test from Stage A — keep one to validate untextured path).
    writer.AddUiQuadCommand(TextureHandle.None,
        dstX: 300, dstY: 220, dstW: 360, dstH: 100,
        u0: 0, v0: 0, u1: 1, v1: 1,
        color: new Vector4(0.20f * 0.5f, 0.85f * 0.5f, 0.30f * 0.5f, 0.5f));   // premultiplied alpha
};

app.Run(services);
font?.Dispose();
