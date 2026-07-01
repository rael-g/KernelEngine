using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Webgpu.Native;

[StructLayout(LayoutKind.Explicit)]
public partial struct ke_gpu_clear_value
{
    [FieldOffset(0)]
    [NativeTypeName("float[4]")]
    public _color_e__FixedBuffer color;

    [FieldOffset(0)]
    [NativeTypeName("__AnonymousRecord_gpu_enums_L246_C5")]
    public _depth_stencil_e__Struct depth_stencil;

    public partial struct _depth_stencil_e__Struct
    {
        public float depth;

        [NativeTypeName("uint8_t")]
        public byte stencil;
    }

    [InlineArray(4)]
    public partial struct _color_e__FixedBuffer
    {
        public float e0;
    }
}
