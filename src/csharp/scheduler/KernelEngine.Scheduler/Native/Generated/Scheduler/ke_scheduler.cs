using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_scheduler
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_scheduler *, ke_schedule *, ke_scheduler_cadence)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, KernelEngine.Schedule.Native.ke_schedule*, global::KernelEngine.Scheduler.SchedulerCadence, KernelEngine.Result.Native.Result> add_schedule;

    [NativeTypeName("ke_result (*)(ke_scheduler *, float)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, float, KernelEngine.Result.Native.Result> tick;

    [NativeTypeName("ke_result (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, KernelEngine.Result.Native.Result> shutdown;

    [NativeTypeName("void (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, void> request_exit;

    [NativeTypeName("bool (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, bool> exit_requested;

    [NativeTypeName("uint64_t (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, ulong> sequence;

    [NativeTypeName("bool (*)(ke_scheduler *, ke_component_id, uint64_t)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, global::KernelEngine.Ecs.ComponentId, ulong, bool> expired;
}
