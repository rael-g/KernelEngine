using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_phase_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("ke_phase_cadence")]
    public global::KernelEngine.Scheduler.PhaseCadence cadence;

    public bool pipelined;
}
