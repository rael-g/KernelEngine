using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct MeshComponent
{
    public MeshHandle Mesh;
    public MaterialHandle Material;
    public _Primitive_e__FixedBuffer Primitive;
    public System.Numerics.Vector4 BaseColor;

    public float Roughness;
    public uint AlphaMode;

    public float AlphaCutoff;

    public float Ior;

    public float DistortionStrength;
    public uint Layers;

    [InlineArray(32)]
    public partial struct _Primitive_e__FixedBuffer
    {
        public sbyte e0;
    }
}
