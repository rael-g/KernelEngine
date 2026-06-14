using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class LabelContributor : IFrameContributor
{
    private readonly NodeWorld _nodeWorld;
    private readonly IWindow   _window;

    public LabelContributor(NodeWorld nodeWorld, IWindow window)
    {
        _nodeWorld = nodeWorld;
        _window    = window;
    }

    public void Contribute(IFramePacket packet)
    {
        var labels = _nodeWorld.Labels;
        if (labels.Count == 0) return;

        var sizeResult = _window.GetSize();
        if (sizeResult.Value.Width == 0 || sizeResult.Value.Height == 0) return;
        float bbW = sizeResult.Value.Width;
        float bbH = sizeResult.Value.Height;

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
                packet.AddUiQuadCommand(atlas,
                    dstX: x, dstY: y, dstW: g.Width, dstH: g.Height,
                    u0: g.U0, v0: g.V0, u1: g.U1, v1: g.V1,
                    r: premul.X, g: premul.Y, b: premul.Z, a: premul.W);
                pen += g.AdvanceX;
            }
        }
    }
}
