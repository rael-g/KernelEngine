namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_resource_cache_handle
{
    public ke_resource_cache* @ref;

    [NativeTypeName("void (*)(ke_resource_cache *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, void> destroy;
}
