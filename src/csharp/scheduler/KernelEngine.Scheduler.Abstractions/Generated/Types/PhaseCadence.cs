using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Scheduler;

public enum PhaseCadence : uint
{
    EveryTick = 0,
    Fixed = 1,
    Startup = 2,
    Shutdown = 3,
}
