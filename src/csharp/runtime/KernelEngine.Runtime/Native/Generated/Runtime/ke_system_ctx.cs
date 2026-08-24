using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_system_ctx
{
    public void* handle;

    [NativeTypeName("const ke_ecs_segment *(*)(ke_system_ctx *, uint32_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, uint, nuint*, KernelEngine.Ecs.Native.ke_ecs_segment*> view;

    [NativeTypeName("ke_entity (*)(ke_system_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, ulong> reserve;

    [NativeTypeName("bool (*)(ke_system_ctx *, ke_defer_fn, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, delegate* unmanaged[Cdecl]<KernelEngine.Ecs.Native.ke_ecs*, void*, void>, void*, nuint, bool> defer;

    [NativeTypeName("ke_entity (*)(ke_system_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, ulong> spawn;

    [NativeTypeName("bool (*)(ke_system_ctx *, ke_entity, ke_component_id, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, ulong, uint, void*, nuint, bool> attach;

    [NativeTypeName("bool (*)(ke_system_ctx *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, ulong, uint, bool> detach;

    [NativeTypeName("bool (*)(ke_system_ctx *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, ulong, bool> despawn;

    [NativeTypeName("void (*)(ke_system_ctx *, uint32_t *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, uint*, uint*, void> slice;
}
