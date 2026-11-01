using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct UiQuadComponent
{
    public uint TextureBits;

    public float DstX;

    public float DstY;

    public float DstW;

    public float DstH;

    public float U0;

    public float V0;

    public float U1;

    public float V1;
    public _Color_e__FixedBuffer Color;

    [InlineArray(4)]
    public partial struct _Color_e__FixedBuffer
    {
        public float e0;
    }
}
