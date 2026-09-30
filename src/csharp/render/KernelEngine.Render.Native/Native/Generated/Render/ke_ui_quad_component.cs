using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_ui_quad_component
{
    [NativeTypeName("uint32_t")]
    public uint texture_bits;

    public float dst_x;

    public float dst_y;

    public float dst_w;

    public float dst_h;

    public float u0;

    public float v0;

    public float u1;

    public float v1;

    [NativeTypeName("float[4]")]
    public _color_e__FixedBuffer color;

    [InlineArray(4)]
    public partial struct _color_e__FixedBuffer
    {
        public float e0;
    }
}
