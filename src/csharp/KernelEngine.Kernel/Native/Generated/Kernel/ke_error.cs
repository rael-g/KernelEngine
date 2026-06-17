namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_error
{
    [NativeTypeName("const ke_error_type *")]
    public ke_error_type* type;

    [NativeTypeName("const char *")]
    public sbyte* message;

    [NativeTypeName("const char *")]
    public sbyte* domain;
}
