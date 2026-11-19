using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Part;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Part.Native;

public unsafe partial struct ke_part_hooked
{
    [NativeTypeName("ke_schedule *")]
    public KernelEngine.Schedule.Native.ke_schedule* schedule;

    [NativeTypeName("ke_schedule_set_id")]
    public uint set;
}
