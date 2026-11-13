using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Schedule;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Schedule.Native;

public unsafe partial struct ke_schedule_set_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("const ke_schedule_set_id *")]
    public uint* after;

    [NativeTypeName("uint32_t")]
    public uint after_count;
}
