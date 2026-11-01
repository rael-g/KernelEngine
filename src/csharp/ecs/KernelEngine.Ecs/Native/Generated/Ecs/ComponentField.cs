using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ComponentField
{
    [NativeTypeName("const char *")]
    public sbyte* Name;

    [NativeTypeName("ke_variant_type")]
    public global::KernelEngine.Ecs.VariantType Type;

    [NativeTypeName("uint32_t")]
    public uint Offset;

    [NativeTypeName("uint32_t")]
    public uint Size;

    [NativeTypeName("ke_variant")]
    public Variant DefaultValue;
}
