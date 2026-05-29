using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
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
    .AddKernel()
    .AddLogger().AddConsoleSink(LogLevel.Warning)
    .AddGlfwWindow(960, 540, "KernelEngine — 14 UI Quad")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnUpdate = (writer, _) =>
{
    writer.ClearColor(0.10f, 0.12f, 0.16f, 1f);

    // Top-left: opaque red rectangle.
    writer.AddUiQuadCommand(TextureHandle.None,
        dstX: 40, dstY: 40, dstW: 240, dstH: 80,
        u0: 0, v0: 0, u1: 1, v1: 1,
        color: new Vector4(1f, 0.20f, 0.20f, 1f));

    // Centered: semi-transparent green band.
    writer.AddUiQuadCommand(TextureHandle.None,
        dstX: 300, dstY: 220, dstW: 360, dstH: 100,
        u0: 0, v0: 0, u1: 1, v1: 1,
        color: new Vector4(0.20f * 0.5f, 0.85f * 0.5f, 0.30f * 0.5f, 0.5f));   // premultiplied alpha

    // Bottom-right: opaque blue rectangle.
    writer.AddUiQuadCommand(TextureHandle.None,
        dstX: 680, dstY: 420, dstW: 240, dstH: 80,
        u0: 0, v0: 0, u1: 1, v1: 1,
        color: new Vector4(0.20f, 0.50f, 1f, 1f));
};

app.Run(services);
