using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_label_component
{
    [NativeTypeName("char[128]")]
    public _font_e__FixedBuffer font;

    public float font_size;

    public ke_ui_font_handle font_handle;

    [NativeTypeName("float[2]")]
    public _anchor_e__FixedBuffer anchor;

    [NativeTypeName("float[2]")]
    public _offset_e__FixedBuffer offset;

    [NativeTypeName("float[4]")]
    public _color_e__FixedBuffer color;

    [NativeTypeName("char[256]")]
    public _text_e__FixedBuffer text;

    [NativeTypeName("uint32_t")]
    public uint glyph_count;

    [NativeTypeName("ke_label_glyph_quad[256]")]
    public _glyphs_e__FixedBuffer glyphs;

    [InlineArray(128)]
    public partial struct _font_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(2)]
    public partial struct _anchor_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(2)]
    public partial struct _offset_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _color_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(256)]
    public partial struct _text_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(256)]
    public partial struct _glyphs_e__FixedBuffer
    {
        public ke_label_glyph_quad e0;
    }
}
