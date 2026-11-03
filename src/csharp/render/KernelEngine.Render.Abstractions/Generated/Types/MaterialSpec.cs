using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct MaterialSpec
{
    public _BaseColor_e__FixedBuffer BaseColor;

    public float Metallic;

    public float Roughness;
    public _AlbedoPath_e__FixedBuffer AlbedoPath;
    public _NormalPath_e__FixedBuffer NormalPath;
    public AlphaMode AlphaMode;

    public float AlphaCutoff;

    public float Ior;

    public float DistortionStrength;

    [InlineArray(4)]
    public partial struct _BaseColor_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(256)]
    public partial struct _AlbedoPath_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(256)]
    public partial struct _NormalPath_e__FixedBuffer
    {
        public sbyte e0;
    }
}
