using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct VariantTable
{
    [NativeTypeName("uint32_t")]
    public uint Count;

    [NativeTypeName("const ke_variant_table_entry *")]
    public VariantTableEntry* Entries;
}
