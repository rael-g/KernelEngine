using System.Numerics;

using global::KernelEngine.Common;

using KernelEngine.Result.Native;

namespace KernelEngine.Common.Native;

public unsafe partial struct ke_resource_cache
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, KernelEngine.Result.Native.Result> register_resource;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, KernelEngine.Result.Native.Result> retain;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, uint, KernelEngine.Result.Native.Result> release;

    [NativeTypeName("bool (*)(struct ke_resource_cache *, const char *, ke_resource_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint*, bool> try_get_cached;

    [NativeTypeName("ke_result (*)(struct ke_resource_cache *, const char *, ke_resource_handle)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, uint, KernelEngine.Result.Native.Result> cache_insert;

    [NativeTypeName("void (*)(struct ke_resource_cache *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_cache*, sbyte*, void> cache_evict;
}
