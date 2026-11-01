using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

[StructLayout(LayoutKind.Explicit)]
public partial struct GpuClearValue
{
    [FieldOffset(0)]
    [NativeTypeName("float[4]")]
    public _Color_e__FixedBuffer Color;

    [FieldOffset(0)]
    [NativeTypeName("__AnonymousRecord_gpu_enums_L209_C5")]
    public _DepthStencil_e__Struct DepthStencil;

    public partial struct _DepthStencil_e__Struct
    {
        public float depth;

        [NativeTypeName("uint8_t")]
        public byte stencil;
    }

    [InlineArray(4)]
    public partial struct _Color_e__FixedBuffer
    {
        public float e0;
    }
}
