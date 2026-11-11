using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_scheduler
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_scheduler *, const ke_phase_desc *, ke_phase_id *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, ke_phase_desc*, uint*, KernelEngine.Result.Native.Result> register_phase;

    [NativeTypeName("ke_result (*)(ke_scheduler *, const ke_set_desc *, ke_set_id *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, ke_set_desc*, uint*, KernelEngine.Result.Native.Result> register_set;

    [NativeTypeName("ke_result (*)(ke_scheduler *, const ke_system_desc *, ke_scheduler_system_id *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, ke_system_desc*, ulong*, KernelEngine.Result.Native.Result> register_system;

    [NativeTypeName("ke_result (*)(ke_scheduler *, ke_scheduler_system_id)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, ulong, KernelEngine.Result.Native.Result> unregister_system;

    [NativeTypeName("ke_result (*)(ke_scheduler *, ke_component_id, ke_lifetime)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Scheduler.Lifetime, KernelEngine.Result.Native.Result> declare_lifetime;

    [NativeTypeName("ke_result (*)(ke_scheduler *, ke_component_id, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId, KernelEngine.Result.Native.Result> declare_exclusive;

    [NativeTypeName("ke_result (*)(ke_scheduler *, bool)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, bool, KernelEngine.Result.Native.Result> build;

    [NativeTypeName("ke_result (*)(ke_scheduler *, ke_phase_id, ke_system_order *, uint32_t, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, uint, global::KernelEngine.Scheduler.SystemOrder*, uint, uint*, KernelEngine.Result.Native.Result> describe_phase;

    [NativeTypeName("ke_result (*)(ke_scheduler *, float)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, float, KernelEngine.Result.Native.Result> tick;

    [NativeTypeName("ke_result (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, KernelEngine.Result.Native.Result> shutdown;

    [NativeTypeName("void (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, void> request_exit;

    [NativeTypeName("bool (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, bool> exit_requested;

    [NativeTypeName("ke_ecs_commands *(*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, KernelEngine.Ecs.Native.ke_ecs_commands*> commands;
}
