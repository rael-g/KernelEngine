namespace KernelEngine.Framework.Legacy.Native;

public unsafe partial struct ke_resource_cache
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle, ke_resource_destroy_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, delegate* unmanaged[Cdecl]<uint, void*, void>, void*, ke_result> register_resource;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, ke_result> retain;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, ke_result> release;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, const char *, ke_resource_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint*, byte> try_get_cached;

    [NativeTypeName("void (*)(struct ke_resource_cache *, const char *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint, void> cache_insert;

    [NativeTypeName("void (*)(struct ke_resource_cache *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, void> cache_evict;

    [NativeTypeName("void (*)(struct ke_resource_cache *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, void> destroy;
}
