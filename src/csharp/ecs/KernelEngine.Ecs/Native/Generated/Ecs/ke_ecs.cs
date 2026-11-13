using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> entity_create;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.Entity, KernelEngine.Result.Native.Result> entity_destroy;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, const ke_component_params *, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ke_component_params*, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> component_register;

    [NativeTypeName("bool (*)(struct ke_ecs *, const char *, ke_component_meta *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, sbyte*, ComponentMeta*, bool> component_lookup;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity, ke_component_id, void **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId, void**, KernelEngine.Result.Native.Result> component_add;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId, KernelEngine.Result.Native.Result> component_remove;

    [NativeTypeName("void *(*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId, void*> component_get;

    [NativeTypeName("size_t (*)(struct ke_ecs *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId, nuint> component_size;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, void *, const ke_component_field *, const ke_variant *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, void*, ke_component_field*, Variant*, KernelEngine.Result.Native.Result> component_field_write;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, const ke_ecs_query_desc *, ke_query_id *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ke_ecs_query_desc*, ulong*, KernelEngine.Result.Native.Result> query_register;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_query_id, ke_ecs_segment *, size_t, void **, ke_component_id *, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, ke_ecs_segment*, nuint, void**, global::KernelEngine.Ecs.ComponentId*, nuint*, KernelEngine.Result.Native.Result> query_resolve;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> entity_reserve;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.Entity, KernelEngine.Result.Native.Result> entity_materialize;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_component_id, void **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId, void**, KernelEngine.Result.Native.Result> singleton_add;

    [NativeTypeName("void *(*)(struct ke_ecs *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId, void*> singleton_get;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId, KernelEngine.Result.Native.Result> singleton_remove;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_component_id, ke_entity, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> pair;

    [NativeTypeName("bool (*)(struct ke_ecs *, ke_component_id, ke_component_id *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId*, global::KernelEngine.Ecs.Entity*, bool> pair_parts;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_component_id, ke_removal_tracker *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.RemovalTracker*, KernelEngine.Result.Native.Result> removal_track;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_removal_tracker, ke_entity *, size_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.RemovalTracker, global::KernelEngine.Ecs.Entity*, nuint, nuint*, KernelEngine.Result.Native.Result> removals;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_entity, ke_component_id *, size_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId*, nuint, nuint*, KernelEngine.Result.Native.Result> entity_components;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, ke_component_id *, size_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId*, nuint, nuint*, KernelEngine.Result.Native.Result> components;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, const ke_component_id *, uint32_t, ke_ecs_snapshot **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, global::KernelEngine.Ecs.ComponentId*, uint, ke_ecs_snapshot**, KernelEngine.Result.Native.Result> snapshot;

    [NativeTypeName("ke_result (*)(struct ke_ecs *, const ke_ecs_snapshot *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ke_ecs_snapshot*, KernelEngine.Result.Native.Result> restore;

    [NativeTypeName("void (*)(struct ke_ecs *, ke_ecs_snapshot *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ke_ecs_snapshot*, void> snapshot_free;
}
