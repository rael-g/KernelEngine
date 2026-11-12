using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Scheduler;

public enum SchedulerCadence : uint
{
    EveryTick = 0,
    Fixed = 1,
    Startup = 2,
    Shutdown = 3,
}
