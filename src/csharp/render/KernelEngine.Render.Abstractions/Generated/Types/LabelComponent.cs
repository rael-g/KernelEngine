using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct LabelComponent
{
    public _FontBytes_e__FixedBuffer FontBytes;

    public float FontSize;
    public UiFontHandle FontHandle;
    public _Anchor_e__FixedBuffer Anchor;
    public _Offset_e__FixedBuffer Offset;
    public _Color_e__FixedBuffer Color;
    public _TextBytes_e__FixedBuffer TextBytes;
    public uint GlyphCount;
    public _Glyphs_e__FixedBuffer Glyphs;

    [InlineArray(128)]
    public partial struct _FontBytes_e__FixedBuffer
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
    public partial struct _TextBytes_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(256)]
    public partial struct _Glyphs_e__FixedBuffer
    {
        public LabelGlyphQuad e0;
    }
}
