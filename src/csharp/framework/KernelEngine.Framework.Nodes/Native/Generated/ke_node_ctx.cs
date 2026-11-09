using System.Numerics;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Asset.Native;
using KernelEngine.Audio.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Framework.Nodes.Native;

public unsafe partial struct ke_node_ctx
{
    public void* handle;

    [NativeTypeName("ke_entity")]
    public global::KernelEngine.Ecs.Entity self;

    public void* fields;

    [NativeTypeName("const void *")]
    public void* @event;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId event_type;

    public float dt;

    [NativeTypeName("ke_ecs_commands *")]
    public KernelEngine.Ecs.Native.ke_ecs_commands* commands;

    [NativeTypeName("bool (*)(ke_node_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, bool> next;

    [NativeTypeName("void *(*)(ke_node_ctx *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.ComponentId, void*> get;

    [NativeTypeName("void *(*)(ke_node_ctx *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId, void*> component;

    [NativeTypeName("ke_entity (*)(ke_node_ctx *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity> parent;

    [NativeTypeName("ke_entity (*)(ke_node_ctx *, ke_entity, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.Entity, sbyte*, global::KernelEngine.Ecs.Entity> child;

    [NativeTypeName("ke_entity (*)(ke_node_ctx *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity> first_child;

    [NativeTypeName("ke_entity (*)(ke_node_ctx *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity> next_sibling;

    [NativeTypeName("ke_entity (*)(ke_node_ctx *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.Entity> ancestor;

    [NativeTypeName("float (*)(ke_node_ctx *, ke_action_ref *)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, ActionRef*, float> axis;

    [NativeTypeName("bool (*)(ke_node_ctx *, ke_action_ref *)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, ActionRef*, bool> pressed;

    [NativeTypeName("ke_result (*)(ke_node_ctx *, ke_component_id, const char *, ke_entity, const ke_node_component *, uint32_t, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.ComponentId, sbyte*, global::KernelEngine.Ecs.Entity, ke_node_component*, uint, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> spawn;

    [NativeTypeName("ke_result (*)(ke_node_ctx *, const char *, const char *, ke_entity, const ke_node_field_value *, uint32_t, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, sbyte*, sbyte*, global::KernelEngine.Ecs.Entity, ke_node_field_value*, uint, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> spawn_named;

    [NativeTypeName("ke_result (*)(ke_node_ctx *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.Entity, KernelEngine.Result.Native.Result> destroy;

    [NativeTypeName("ke_result (*)(ke_node_ctx *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, sbyte*, KernelEngine.Result.Native.Result> change_scene;

    [NativeTypeName("ke_result (*)(ke_node_ctx *, ke_component_id, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, global::KernelEngine.Ecs.ComponentId, void*, nuint, KernelEngine.Result.Native.Result> raise;

    [NativeTypeName("void (*)(ke_node_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, void> exit;
}
