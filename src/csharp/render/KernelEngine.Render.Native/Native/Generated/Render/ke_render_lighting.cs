using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_render_lighting
{
    [NativeTypeName("float[4]")]
    public _direction_e__FixedBuffer direction;

    [NativeTypeName("float[4]")]
    public _color_e__FixedBuffer color;

    [NativeTypeName("float[4]")]
    public _ambient_e__FixedBuffer ambient;

    [InlineArray(4)]
    public partial struct _direction_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _color_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _ambient_e__FixedBuffer
    {
        public float e0;
    }
}
