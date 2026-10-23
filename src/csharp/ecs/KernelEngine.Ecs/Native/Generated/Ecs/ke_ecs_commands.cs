using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs_commands
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, ulong*, KernelEngine.Result.Native.ke_result> spawn;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_entity, ke_component_id, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, ulong, uint, void*, nuint, KernelEngine.Result.Native.ke_result> attach;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, ulong, uint, KernelEngine.Result.Native.ke_result> detach;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, ulong, KernelEngine.Result.Native.ke_result> despawn;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_defer_fn, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, delegate* unmanaged[Cdecl]<ke_ecs*, void*, void>, void*, nuint, KernelEngine.Result.Native.ke_result> defer;
}
