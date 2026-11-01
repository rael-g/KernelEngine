using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public partial struct LabelComponent
{
    [NativeTypeName("char[128]")]
    public _Font_e__FixedBuffer Font;

    public float FontSize;

    public ke_ui_font_handle FontHandle;

    [NativeTypeName("float[2]")]
    public _Anchor_e__FixedBuffer Anchor;

    [NativeTypeName("float[2]")]
    public _Offset_e__FixedBuffer Offset;

    [NativeTypeName("float[4]")]
    public _Color_e__FixedBuffer Color;

    [NativeTypeName("char[256]")]
    public _Text_e__FixedBuffer Text;

    [NativeTypeName("uint32_t")]
    public uint GlyphCount;

    [NativeTypeName("ke_label_glyph_quad[256]")]
    public _Glyphs_e__FixedBuffer Glyphs;

    [InlineArray(128)]
    public partial struct _Font_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(2)]
    public partial struct _Anchor_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(2)]
    public partial struct _Offset_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _Color_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(256)]
    public partial struct _Text_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(256)]
    public partial struct _Glyphs_e__FixedBuffer
    {
        public global::KernelEngine.Render.LabelGlyphQuad e0;
    }
}
