using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs
{
    public void* handle;

    [NativeTypeName("ke_entity (*)(struct ke_ecs *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong> entity_create;

    [NativeTypeName("void (*)(struct ke_ecs *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, void> entity_destroy;

    [NativeTypeName("ke_component_id (*)(struct ke_ecs *, const char *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, sbyte*, nuint, uint> component_register;

    [NativeTypeName("bool (*)(struct ke_ecs *, const char *, ke_component_meta *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, sbyte*, ke_component_meta*, ke_error**, bool> component_lookup;

    [NativeTypeName("void *(*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, void*> component_add;

    [NativeTypeName("void (*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, void> component_remove;

    [NativeTypeName("void *(*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, void*> component_get;

    [NativeTypeName("size_t (*)(struct ke_ecs *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, uint, nuint> component_size;

    [NativeTypeName("ke_query_id (*)(struct ke_ecs *, const ke_component_id *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, uint*, nuint, ulong> query_register;

    [NativeTypeName("void (*)(struct ke_ecs *, ke_query_id, ke_ecs_segment *, size_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, ke_ecs_segment*, nuint, nuint*, void> query_resolve;

    [NativeTypeName("ke_entity (*)(struct ke_ecs *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong> entity_reserve;
}
