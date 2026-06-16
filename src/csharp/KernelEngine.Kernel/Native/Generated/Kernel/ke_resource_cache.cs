namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_resource_cache
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, int> register_resource;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, int> retain;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, int> release;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, const char *, ke_resource_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint*, bool> try_get_cached;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, const char *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint, int> cache_insert;

    [NativeTypeName("void (*)(struct ke_resource_cache *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, void> cache_evict;

    [NativeTypeName("void (*)(struct ke_resource_cache *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, void> destroy;
}
