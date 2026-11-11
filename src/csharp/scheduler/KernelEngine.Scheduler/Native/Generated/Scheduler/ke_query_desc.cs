using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_query_desc
{
    [NativeTypeName("const ke_id_access *")]
    public global::KernelEngine.Scheduler.IdAccess* terms;

    [NativeTypeName("uint32_t")]
    public uint term_count;
}
