using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Emits <see cref="Label"/> glyphs as UI quads into the FramePacket each sim frame. Auto-registered
/// by <see cref="Application"/> alongside the other render systems.
/// </summary>
/// <remarks>
/// MVP layout: single-line, pen advances horizontally from a label-local origin computed via
/// <see cref="Label.Anchor"/> × backbuffer size + <see cref="Label.Offset"/> − pivot offset. The
/// pivot is determined by <see cref="Label.Anchor"/> applied to the label's measured size + ascent,
/// so <c>Anchor=(0.5, 0)</c> centers the text horizontally and aligns its top to the anchor line.
/// </remarks>
public sealed class LabelRenderSystem : ISystem
{
    private readonly Func<(uint width, uint height)> _backbufferSize;

    public LabelRenderSystem(Func<(uint width, uint height)> backbufferSize)
    {
        _backbufferSize = backbufferSize;
    }

    public void Update(IWorld world, float deltaTime, IFramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;

        var labels = Label.Snapshot();
        if (labels.Count == 0) return;

        var (bbW, bbH) = _backbufferSize();
        if (bbW == 0 || bbH == 0) return;

        foreach (var label in labels)
        {
            var font = label.Font;
            if (font == null || string.IsNullOrEmpty(label.Text)) continue;

            // Measure to compute pivot offsets.
            float textWidth = font.MeasureWidth(label.Text);
            // Label "height" for pivot purposes = ascent (top-of-glyphs to baseline).
            float textHeight = font.Ascent;

            // Anchor in pixels (where the label is placed on screen).
            float anchorX = label.Anchor.X * bbW + label.Offset.X;
            float anchorY = label.Anchor.Y * bbH + label.Offset.Y;

            // Pivot subtract: anchor in label-local coords.
            float pivotX = label.Anchor.X * textWidth;
            float pivotY = label.Anchor.Y * textHeight;

            // Origin = top-left of the label rect, then baseline is `ascent` pixels below.
            float originX  = anchorX - pivotX;
            float baselineY = anchorY - pivotY + font.Ascent;

            // Premultiply alpha so it composes correctly with the UI shader's BLEND_ONE/INV_SRC_ALPHA.
            var c = label.Color;
            var premul = new System.Numerics.Vector4(c.X * c.W, c.Y * c.W, c.Z * c.W, c.W);

            // Walk codepoints + emit a quad per glyph (ASCII only — no UTF-8 decoding yet).
            float pen = originX;
            var atlas = font.Atlas.Handle;
            foreach (var ch in label.Text)
            {
                if (!font.TryGlyph(ch, out var g))
                {
                    // Unknown codepoint — skip + advance by a default em fraction. Keeps layout
                    // stable for placeholder/missing glyphs without aborting the whole string.
                    pen += font.LineHeight * 0.25f;
                    continue;
                }

                float x = pen + g.BearingX;
                float y = baselineY - g.BearingY;
                packet.AddUiQuadCommand(atlas,
                    dstX: x, dstY: y, dstW: g.Width, dstH: g.Height,
                    u0: g.U0, v0: g.V0, u1: g.U1, v1: g.V1,
                    r: premul.X, g: premul.Y, b: premul.Z, a: premul.W);
                pen += g.AdvanceX;
            }
        }
    }
}
