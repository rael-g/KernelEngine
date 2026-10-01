using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs_commands
{
    public void* handle;

    [NativeTypeName("ke_entity (*)(ke_ecs_commands *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, KernelEngine.Common.Native.ke_error**, ulong> spawn;

    [NativeTypeName("bool (*)(ke_ecs_commands *, ke_entity, ke_component_id, const void *, size_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, ulong, uint, void*, nuint, KernelEngine.Common.Native.ke_error**, bool> attach;

    [NativeTypeName("bool (*)(ke_ecs_commands *, ke_entity, ke_component_id, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, ulong, uint, KernelEngine.Common.Native.ke_error**, bool> detach;

    [NativeTypeName("bool (*)(ke_ecs_commands *, ke_entity, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, ulong, KernelEngine.Common.Native.ke_error**, bool> despawn;

    [NativeTypeName("bool (*)(ke_ecs_commands *, ke_defer_fn, const void *, size_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, delegate* unmanaged[Cdecl]<ke_ecs*, void*, void>, void*, nuint, KernelEngine.Common.Native.ke_error**, bool> defer;
}
