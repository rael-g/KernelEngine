using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_script_host
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_script_host *, const char *, const ke_component_id *, uint32_t, ke_script_reach, ke_script_type_id *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, sbyte*, uint*, uint, ke_script_reach, uint*, KernelEngine.Common.Native.ke_error**, bool> register_type;

    [NativeTypeName("bool (*)(struct ke_script_host *, const char *, ke_script_type_id *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, sbyte*, uint*, bool> type_lookup;

    [NativeTypeName("const ke_component_id *(*)(struct ke_script_host *, ke_script_type_id, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, uint*, uint*> type_components;

    [NativeTypeName("ke_script_reach (*)(struct ke_script_host *, ke_script_type_id)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, ke_script_reach> type_reach;

    [NativeTypeName("bool (*)(struct ke_script_host *, ke_entity, ke_script_type_id, void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, ulong, uint, void*, KernelEngine.Common.Native.ke_error**, bool> bind;

    [NativeTypeName("void (*)(struct ke_script_host *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, ulong, void> unbind;

    [NativeTypeName("bool (*)(struct ke_script_host *, ke_entity, ke_script_type_id, void *, ke_ecs_commands *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, ulong, uint, void*, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Common.Native.ke_error**, bool> bind_deferred;

    [NativeTypeName("bool (*)(struct ke_script_host *, ke_entity, ke_ecs_commands *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, ulong, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Common.Native.ke_error**, bool> unbind_deferred;

    [NativeTypeName("bool (*)(struct ke_script_host *, ke_entity, ke_script_type_id *, void **)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, ulong, uint*, void**, bool> instance_of;

    [NativeTypeName("uint32_t (*)(struct ke_script_host *, ke_script_type_id)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, uint> instance_count;

    [NativeTypeName("const ke_entity *(*)(struct ke_script_host *, ke_script_type_id, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, uint, uint*, ulong*> instances;

    [NativeTypeName("ke_entity (*)(struct ke_script_host *, ke_entity, ke_script_type_id, const char *, ke_script_borrow, ke_script_resolve *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, ulong, uint, sbyte*, ke_script_borrow, ke_script_resolve*, ulong> resolve;
}
