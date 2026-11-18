using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Completion.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Job.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Schedule.Native;

public unsafe partial struct ke_schedule_system_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public void* user_data;

    [NativeTypeName("ke_schedule_execute_fn")]
    public delegate* unmanaged[Cdecl]<ke_schedule_ctx*, void*, float, KernelEngine.Result.Native.Result> execute;

    [NativeTypeName("ke_schedule_condition_fn")]
    public delegate* unmanaged[Cdecl]<void*, bool*, KernelEngine.Result.Native.Result> condition;

    [NativeTypeName("const ke_ecs_query_desc *")]
    public KernelEngine.Ecs.Native.ke_ecs_query_desc* queries;

    [NativeTypeName("uint32_t")]
    public uint query_count;

    [NativeTypeName("const ke_ecs_query_term *")]
    public global::KernelEngine.Ecs.EcsQueryTerm* access;

    [NativeTypeName("uint32_t")]
    public uint access_count;

    [NativeTypeName("const ke_schedule_set_id *")]
    public uint* sets;

    [NativeTypeName("uint32_t")]
    public uint set_count;

    public bool per_entity;

    public bool exclusive;
}
