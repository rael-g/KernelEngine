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

public unsafe partial struct ke_node_types
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_node_types *, const ke_node_type_desc *, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_node_types*, ke_node_type_desc*, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> register_type;

    [NativeTypeName("ke_result (*)(struct ke_node_types *, const ke_component_params *, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_node_types*, KernelEngine.Ecs.Native.ke_component_params*, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> register_event;

    [NativeTypeName("ke_result (*)(struct ke_node_types *, ke_ecs_commands *, ke_component_id, const char *, ke_entity, const ke_node_component *, uint32_t, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_node_types*, KernelEngine.Ecs.Native.ke_ecs_commands*, global::KernelEngine.Ecs.ComponentId, sbyte*, global::KernelEngine.Ecs.Entity, ke_node_component*, uint, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> spawn;

    [NativeTypeName("ke_result (*)(struct ke_node_types *, const char *, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_node_types*, sbyte*, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> find_type;

    [NativeTypeName("ke_result (*)(struct ke_node_types *, const char *, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_node_types*, sbyte*, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> find_component;

    [NativeTypeName("const void *(*)(struct ke_node_types *, ke_component_id, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_node_types*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId, void*> initial;

    [NativeTypeName("bool (*)(struct ke_node_types *, ke_component_id, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_node_types*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId, bool> carries;
}
