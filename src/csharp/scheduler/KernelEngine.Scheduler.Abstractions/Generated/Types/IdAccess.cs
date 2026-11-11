using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Scheduler;

public partial struct IdAccess
{
    public global::KernelEngine.Ecs.ComponentId Id;
    public SchedulerAccess Access;
}
