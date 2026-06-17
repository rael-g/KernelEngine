namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_scene_properties
{
    [NativeTypeName("const ke_variant_table_entry *")]
    public ke_variant_table_entry* entries;

    [NativeTypeName("uint32_t")]
    public uint count;
}
