using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Scheduler;

public partial struct SchedulerConfig
{
    public float FixedDt;

    public float FixedDtMaxAccum;
}
