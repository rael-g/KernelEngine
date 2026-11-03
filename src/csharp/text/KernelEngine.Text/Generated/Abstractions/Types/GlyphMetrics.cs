using System.Numerics;

namespace KernelEngine.Text;

public partial struct GlyphMetrics
{
    public uint Codepoint;

    public float U0;

    public float V0;

    public float U1;

    public float V1;

    public float BearingX;

    public float BearingY;

    public float Width;

    public float Height;

    public float AdvanceX;
}
