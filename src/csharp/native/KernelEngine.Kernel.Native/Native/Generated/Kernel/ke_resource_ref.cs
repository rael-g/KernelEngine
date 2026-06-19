namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_resource_ref
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_resource_access access;
}
