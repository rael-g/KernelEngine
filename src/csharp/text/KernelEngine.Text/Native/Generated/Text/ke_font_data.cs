using KernelEngine.Common.Native;

namespace KernelEngine.Text.Native;

public unsafe partial struct ke_font_data
{
    [NativeTypeName("uint8_t *")]
    public byte* atlas_rgba;

    [NativeTypeName("uint32_t")]
    public uint atlas_width;

    [NativeTypeName("uint32_t")]
    public uint atlas_height;

    public ke_glyph_metrics* glyphs;

    [NativeTypeName("uint32_t")]
    public uint glyph_count;

    public float line_height;

    public float ascent;
}
