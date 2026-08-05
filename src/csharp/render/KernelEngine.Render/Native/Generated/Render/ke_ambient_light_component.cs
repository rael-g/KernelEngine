using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_ambient_light_component
{
    [NativeTypeName("float[3]")]
    public _color_e__FixedBuffer color;

    [InlineArray(3)]
    public partial struct _color_e__FixedBuffer
    {
        public float e0;
    }
}
