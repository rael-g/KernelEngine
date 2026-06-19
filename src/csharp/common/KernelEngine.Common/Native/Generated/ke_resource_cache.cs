namespace KernelEngine.Common.Native;

public unsafe partial struct ke_resource_cache
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, ke_error**, ke_result> register_resource;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, ke_error**, ke_result> retain;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, ke_error**, ke_result> release;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, const char *, ke_resource_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint*, bool> try_get_cached;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, const char *, ke_resource_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint, ke_error**, ke_result> cache_insert;

    [NativeTypeName("void (*)(struct ke_resource_cache *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, void> cache_evict;
}
