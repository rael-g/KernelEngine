using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_spot_light_component
{
    [NativeTypeName("float[3]")]
    public _direction_e__FixedBuffer direction;

    [NativeTypeName("float[3]")]
    public _color_e__FixedBuffer color;

    public float intensity;

    public float range;

    public float inner_angle;

    public float outer_angle;

    [InlineArray(3)]
    public partial struct _direction_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(3)]
    public partial struct _color_e__FixedBuffer
    {
        public float e0;
    }
}
