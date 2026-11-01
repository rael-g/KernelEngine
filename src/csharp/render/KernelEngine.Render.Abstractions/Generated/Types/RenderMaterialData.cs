using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct RenderMaterialData
{
    public _BaseColor_e__FixedBuffer BaseColor;

    public float Metallic;

    public float Roughness;

    public float AlphaCutoff;

    public float Ior;

    public float DistortionStrength;
    public ulong Albedo;
    public ulong NormalMap;

    [InlineArray(4)]
    public partial struct _BaseColor_e__FixedBuffer
    {
        public float e0;
    }
}
