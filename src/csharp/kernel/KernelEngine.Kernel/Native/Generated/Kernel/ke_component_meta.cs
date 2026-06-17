namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_component_meta
{
    [NativeTypeName("ke_component_id")]
    public uint cid;

    [NativeTypeName("size_t")]
    public nuint size;

    [NativeTypeName("const ke_component_field *")]
    public ke_component_field* fields;

    [NativeTypeName("uint32_t")]
    public uint field_count;
}
