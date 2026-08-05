using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_directional_light_component
{
    [NativeTypeName("float[3]")]
    public _direction_e__FixedBuffer direction;

    [NativeTypeName("float[3]")]
    public _color_e__FixedBuffer color;

    public float intensity;

    [NativeTypeName("float[3]")]
    public _ambient_e__FixedBuffer ambient;

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

    [InlineArray(3)]
    public partial struct _ambient_e__FixedBuffer
    {
        public float e0;
    }
}
