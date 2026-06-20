namespace KernelEngine.Common.Native;

public unsafe partial struct ke_error_type
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("const struct ke_error_type *")]
    public ke_error_type* parent;
}
