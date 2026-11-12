using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Schedule;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Schedule.Native;

public unsafe partial struct ke_schedule
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_schedule *, const ke_schedule_set_desc *, ke_schedule_set_id *)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, ke_schedule_set_desc*, uint*, KernelEngine.Result.Native.Result> register_set;

    [NativeTypeName("ke_result (*)(ke_schedule *, const ke_schedule_system_desc *, ke_schedule_system_id *)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, ke_schedule_system_desc*, ulong*, KernelEngine.Result.Native.Result> register_system;

    [NativeTypeName("ke_result (*)(ke_schedule *, ke_schedule_system_id)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, ulong, KernelEngine.Result.Native.Result> unregister_system;

    [NativeTypeName("ke_result (*)(ke_schedule *, ke_component_id, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId, KernelEngine.Result.Native.Result> declare_exclusive;

    [NativeTypeName("ke_result (*)(ke_schedule *, bool)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, bool, KernelEngine.Result.Native.Result> build;

    [NativeTypeName("ke_result (*)(ke_schedule *, ke_schedule_system_order *, uint32_t, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, global::KernelEngine.Schedule.ScheduleSystemOrder*, uint, uint*, KernelEngine.Result.Native.Result> describe;

    [NativeTypeName("ke_result (*)(ke_schedule *, float)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, float, KernelEngine.Result.Native.Result> run;

    [NativeTypeName("ke_ecs_commands *(*)(ke_schedule *)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, KernelEngine.Ecs.Native.ke_ecs_commands*> commands;
}
