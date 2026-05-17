namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_dev_platform
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_dev_platform *)")]
    public delegate* unmanaged[Cdecl]<ke_dev_platform*, void> destroy;

    [NativeTypeName("void (*)(struct ke_dev_platform *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_dev_platform*, sbyte*, void> set_thread_name;
}
