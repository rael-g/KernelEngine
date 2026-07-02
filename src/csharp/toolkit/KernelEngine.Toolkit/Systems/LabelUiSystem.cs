using System.Numerics;
using KernelEngine.Render;
using KernelEngine.Window;

namespace KernelEngine.Framework;

/// <summary>
/// Expands every <see cref="Label"/> node into <see cref="IRenderResources.UiQuad"/>
/// calls, one per glyph. render-v2's equivalent of the legacy bgfx <c>LabelContributor</c>
/// — the render module has no frame-packet/contributor bridge, so this runs as an
/// ordinary runtime system instead.
/// </summary>
internal static class LabelUiSystem
{
    /// <summary>
    /// Registers the emission system at <see cref="KernelEngine.Runtime.RuntimePhase.Update"/>.
    /// Must run there (not <c>Render</c>): the render module's "render.ui" native pass is
    /// registered as one atomic block inside <c>WebgpuRenderModule.OnLoad</c>, which always
    /// runs before this module's systems register — so a system registered in the Render
    /// phase could never be ordered ahead of it. Emitting during Update instead works because
    /// phases run strictly in order within a tick (Update completes before Render starts) and
    /// the render core's UI quad list is drained (not cleared) by the ui pass itself, so quads
    /// queued this tick's Update are exactly what this tick's Render draws.
    /// </summary>
    public static void Register(KernelEngine.Runtime.IRuntime runtime, NodeWorld nodeWorld,
                                IRenderResources resources, IWindow window)
    {
        runtime.RegisterSystem("Scene.LabelsToUi", KernelEngine.Runtime.RuntimePhase.Update, (_, _) =>
        {
            var labels = nodeWorld.Labels;
            if (labels.Count == 0) return;

            var size = window.GetSize();
            if (size.Width == 0 || size.Height == 0) return;
            float bbW = size.Width;
            float bbH = size.Height;

            for (int i = 0; i < labels.Count; i++)
            {
                var label = labels[i];
                var font  = label.Font;
                if (font == null || string.IsNullOrEmpty(label.Text)) continue;

                float textWidth  = font.MeasureWidth(label.Text);
                float textHeight = font.Ascent;

                float anchorX = label.Anchor.X * bbW + label.Offset.X;
                float anchorY = label.Anchor.Y * bbH + label.Offset.Y;
                float pivotX  = label.Anchor.X * textWidth;
                float pivotY  = label.Anchor.Y * textHeight;

                float originX   = anchorX - pivotX;
                float baselineY = anchorY - pivotY + font.Ascent;

                var c      = label.Color;
                var premul = new Vector4(c.X * c.W, c.Y * c.W, c.Z * c.W, c.W);

                float pen   = originX;
                var   atlas = font.AtlasHandle;
                foreach (var ch in label.Text)
                {
                    if (!font.TryGlyph(ch, out var g))
                    {
                        pen += font.LineHeight * 0.25f;
                        continue;
                    }
                    float x = pen + g.BearingX;
                    float y = baselineY - g.BearingY;
                    resources.UiQuad(atlas, x, y, g.Width, g.Height, g.U0, g.V0, g.U1, g.V1, premul);
                    pen += g.AdvanceX;
                }
            }
        }, pinnedThread: 1);
    }
}
