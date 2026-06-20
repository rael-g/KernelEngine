using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_ui_draw_command
{
    public ke_texture_handle texture;

    public float dst_x;

    public float dst_y;

    public float dst_w;

    public float dst_h;

    public float src_u0;

    public float src_v0;

    public float src_u1;

    public float src_v1;

    [NativeTypeName("float[4]")]
    public _color_e__FixedBuffer color;

    [InlineArray(4)]
    public partial struct _color_e__FixedBuffer
    {
        public float e0;
    }
}
