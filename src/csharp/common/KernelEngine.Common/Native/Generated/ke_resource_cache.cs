namespace KernelEngine.Common.Native;

public unsafe partial struct ke_resource_cache
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, ke_resource_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, ke_error**, bool> register_resource;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, ke_resource_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, ke_error**, bool> retain;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, ke_resource_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, ke_error**, bool> release;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, const char *, ke_resource_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint*, bool> try_get_cached;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, const char *, ke_resource_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint, ke_error**, bool> cache_insert;

    [NativeTypeName("void (*)(struct ke_resource_cache *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, void> cache_evict;
}
