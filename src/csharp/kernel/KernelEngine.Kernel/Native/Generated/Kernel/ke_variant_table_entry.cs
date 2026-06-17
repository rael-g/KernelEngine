namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_variant_table_entry
{
    [NativeTypeName("const char *")]
    public sbyte* key;

    public ke_variant value;
}
