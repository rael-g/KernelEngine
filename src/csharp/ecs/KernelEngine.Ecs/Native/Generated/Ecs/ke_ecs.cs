using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong*, KernelEngine.Result.Native.ke_result> entity_create;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, KernelEngine.Result.Native.ke_result> entity_destroy;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, const ke_component_params *, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ke_component_params*, uint*, KernelEngine.Result.Native.ke_result> component_register;

    [NativeTypeName("bool (*)(struct ke_ecs *, const char *, ke_component_meta *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, sbyte*, ke_component_meta*, bool> component_lookup;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity, ke_component_id, void **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, void**, KernelEngine.Result.Native.ke_result> component_add;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, KernelEngine.Result.Native.ke_result> component_remove;

    [NativeTypeName("void *(*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, void*> component_get;

    [NativeTypeName("size_t (*)(struct ke_ecs *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, uint, nuint> component_size;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, void *, const ke_component_field *, const ke_variant *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, void*, ke_component_field*, ke_variant*, KernelEngine.Result.Native.ke_result> component_field_write;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, const ke_component_id *, size_t, ke_query_id *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, uint*, nuint, ulong*, KernelEngine.Result.Native.ke_result> query_register;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_query_id, ke_ecs_segment *, size_t, void **, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, ke_ecs_segment*, nuint, void**, nuint*, KernelEngine.Result.Native.ke_result> query_resolve;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong*, KernelEngine.Result.Native.ke_result> entity_reserve;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, KernelEngine.Result.Native.ke_result> entity_materialize;
}
