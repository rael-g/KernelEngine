using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_component_field
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("ke_variant_type")]
    public global::KernelEngine.Ecs.VariantType type;

    [NativeTypeName("uint32_t")]
    public uint offset;

    [NativeTypeName("uint32_t")]
    public uint size;

    [NativeTypeName("ke_variant")]
    public Variant default_value;

    [NativeTypeName("const char *const *")]
    public sbyte** enum_names;

    [NativeTypeName("uint32_t")]
    public uint enum_count;
}
