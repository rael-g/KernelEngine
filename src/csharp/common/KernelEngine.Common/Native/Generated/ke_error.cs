namespace KernelEngine.Common.Native;

public unsafe partial struct ke_error
{
    [NativeTypeName("const ke_error_type *")]
    public ke_error_type* type;

    [NativeTypeName("const char *")]
    public sbyte* message;

    [NativeTypeName("const char *")]
    public sbyte* file;

    [NativeTypeName("uint32_t")]
    public uint line;

    [NativeTypeName("const struct ke_error *")]
    public ke_error* cause;
}
