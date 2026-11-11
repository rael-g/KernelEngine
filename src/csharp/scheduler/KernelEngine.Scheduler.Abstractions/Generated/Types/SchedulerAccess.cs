using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Scheduler;

public enum SchedulerAccess : uint
{
    Read = 1 << 0,
    Write = 1 << 1,
}
