using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Completion.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Job.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Schedule.Native;

public unsafe partial struct ke_schedule_set
{
    public ke_schedule* schedule;

    [NativeTypeName("ke_schedule_set_id")]
    public uint id;
}
