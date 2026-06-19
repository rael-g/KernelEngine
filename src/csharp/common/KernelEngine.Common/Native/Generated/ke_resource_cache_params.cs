namespace KernelEngine.Common.Native;

public unsafe partial struct ke_resource_cache_params
{
    [NativeTypeName("ke_resource_destroy_func")]
    public delegate* unmanaged[Cdecl]<uint, void*, void> destroy_fn;

    public void* destroy_ctx;
}
