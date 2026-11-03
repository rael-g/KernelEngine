using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct VariantTableEntry
{
    [NativeTypeName("const char *")]
    public sbyte* Key;

    [NativeTypeName("ke_variant")]
    public Variant Value;

    public bool Consumed;
}
