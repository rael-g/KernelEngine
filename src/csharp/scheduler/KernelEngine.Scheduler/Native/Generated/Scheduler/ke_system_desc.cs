using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_system_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public void* user_data;

    [NativeTypeName("ke_scheduler_execute_fn")]
    public delegate* unmanaged[Cdecl]<ke_scheduler_ctx*, void*, float, KernelEngine.Result.Native.Result> execute;

    [NativeTypeName("const ke_query_desc *")]
    public ke_query_desc* queries;

    [NativeTypeName("uint32_t")]
    public uint query_count;

    [NativeTypeName("const ke_id_access *")]
    public global::KernelEngine.Scheduler.IdAccess* access;

    [NativeTypeName("uint32_t")]
    public uint access_count;

    [NativeTypeName("const ke_set_id *")]
    public uint* sets;

    [NativeTypeName("uint32_t")]
    public uint set_count;

    public bool per_entity;

    public bool exclusive;
}
