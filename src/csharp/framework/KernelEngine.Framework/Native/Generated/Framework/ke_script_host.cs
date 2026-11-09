using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_script_host
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_script_host *, const char *, const ke_component_id *, uint32_t, ke_script_reach, ke_script_type_id *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, sbyte*, global::KernelEngine.Ecs.ComponentId*, uint, ScriptReach, uint*, KernelEngine.Result.Native.Result> register_type;

    [NativeTypeName("bool (*)(struct ke_script_host *, const char *, ke_script_type_id *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, sbyte*, uint*, bool> type_lookup;

    [NativeTypeName("ke_result (*)(struct ke_script_host *, const char *, ke_script_type_id)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, sbyte*, uint, KernelEngine.Result.Native.Result> register_type_alias;

    [NativeTypeName("ke_result (*)(struct ke_script_host *, const char *, ke_script_type_id *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, sbyte*, uint*, KernelEngine.Result.Native.Result> type_resolve;

    [NativeTypeName("const ke_component_id *(*)(struct ke_script_host *, ke_script_type_id, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, uint*, global::KernelEngine.Ecs.ComponentId*> type_components;

    [NativeTypeName("ke_script_reach (*)(struct ke_script_host *, ke_script_type_id)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, ScriptReach> type_reach;

    [NativeTypeName("ke_component_id (*)(struct ke_script_host *, ke_script_type_id)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, global::KernelEngine.Ecs.ComponentId> type_tag;

    [NativeTypeName("ke_component_id (*)(struct ke_script_host *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, global::KernelEngine.Ecs.ComponentId> type_tag_group;

    [NativeTypeName("ke_result (*)(struct ke_script_host *, ke_entity, ke_script_type_id, void *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, global::KernelEngine.Ecs.Entity, uint, void*, KernelEngine.Result.Native.Result> bind;

    [NativeTypeName("ke_result (*)(struct ke_script_host *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, global::KernelEngine.Ecs.Entity, KernelEngine.Result.Native.Result> unbind;

    [NativeTypeName("ke_result (*)(struct ke_script_host *, ke_entity, ke_script_type_id, void *, ke_ecs_commands *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, global::KernelEngine.Ecs.Entity, uint, void*, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Result.Native.Result> bind_deferred;

    [NativeTypeName("ke_result (*)(struct ke_script_host *, ke_entity, ke_ecs_commands *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, global::KernelEngine.Ecs.Entity, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Result.Native.Result> unbind_deferred;

    [NativeTypeName("bool (*)(struct ke_script_host *, ke_entity, ke_script_type_id *, void **)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, global::KernelEngine.Ecs.Entity, uint*, void**, bool> instance_of;

    [NativeTypeName("uint32_t (*)(struct ke_script_host *, ke_script_type_id)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, uint> instance_count;

    [NativeTypeName("const ke_entity *(*)(struct ke_script_host *, ke_script_type_id, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, uint*, global::KernelEngine.Ecs.Entity*> instances;

    [NativeTypeName("ke_entity (*)(struct ke_script_host *, ke_entity, const ke_script_type_id *, uint32_t, const char *, ke_script_borrow, ke_script_resolve *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, global::KernelEngine.Ecs.Entity, uint*, uint, sbyte*, ScriptBorrow, ScriptResolve*, global::KernelEngine.Ecs.Entity> resolve;
}
