namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_thread_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("ke_thread_func")]
    public delegate* unmanaged[Cdecl]<void*, void> func;

    public void* user_data;

    public ke_dev_platform* dev_platform;
}
