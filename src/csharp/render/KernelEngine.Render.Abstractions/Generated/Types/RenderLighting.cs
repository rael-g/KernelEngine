using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct RenderLighting
{
    public _Direction_e__FixedBuffer Direction;
    public _Color_e__FixedBuffer Color;
    public _Ambient_e__FixedBuffer Ambient;

    [InlineArray(4)]
    public partial struct _Direction_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _Color_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _Ambient_e__FixedBuffer
    {
        public float e0;
    }
}
