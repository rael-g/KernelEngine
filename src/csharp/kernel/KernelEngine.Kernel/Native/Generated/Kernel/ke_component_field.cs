namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_component_field
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_variant_type type;

    [NativeTypeName("uint32_t")]
    public uint offset;

    [NativeTypeName("uint32_t")]
    public uint size;
}
