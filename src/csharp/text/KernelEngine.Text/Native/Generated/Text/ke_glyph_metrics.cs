using KernelEngine.Common.Native;

namespace KernelEngine.Text.Native;

public partial struct ke_glyph_metrics
{
    [NativeTypeName("uint32_t")]
    public uint codepoint;

    public float u0;

    public float v0;

    public float u1;

    public float v1;

    public float bearing_x;

    public float bearing_y;

    public float width;

    public float height;

    public float advance_x;
}
