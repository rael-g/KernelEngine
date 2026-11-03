using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs_commands
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> spawn;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_entity, ke_component_id, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId, void*, nuint, KernelEngine.Result.Native.Result> attach;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.ComponentId, KernelEngine.Result.Native.Result> detach;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, global::KernelEngine.Ecs.Entity, KernelEngine.Result.Native.Result> despawn;

    [NativeTypeName("ke_result (*)(ke_ecs_commands *, ke_defer_fn, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_ecs_commands*, delegate* unmanaged[Cdecl]<ke_ecs*, void*, KernelEngine.Result.Native.Result>, void*, nuint, KernelEngine.Result.Native.Result> defer;
}
