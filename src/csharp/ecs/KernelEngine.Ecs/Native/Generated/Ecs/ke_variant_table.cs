using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_variant_table
{
    [NativeTypeName("uint32_t")]
    public uint count;

    [NativeTypeName("const ke_variant_table_entry *")]
    public ke_variant_table_entry* entries;
}
