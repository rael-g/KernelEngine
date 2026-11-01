using System.Numerics;

using global::KernelEngine.Text;

using KernelEngine.Result.Native;

namespace KernelEngine.Text.Native;

public unsafe partial struct ke_font_data
{
    [NativeTypeName("uint8_t *")]
    public byte* atlas_rgba;

    [NativeTypeName("uint32_t")]
    public uint atlas_byte_count;

    [NativeTypeName("uint32_t")]
    public uint atlas_width;

    [NativeTypeName("uint32_t")]
    public uint atlas_height;

    [NativeTypeName("ke_glyph_metrics *")]
    public global::KernelEngine.Text.GlyphMetrics* glyphs;

    [NativeTypeName("uint32_t")]
    public uint glyph_count;

    public float line_height;

    public float ascent;
}
