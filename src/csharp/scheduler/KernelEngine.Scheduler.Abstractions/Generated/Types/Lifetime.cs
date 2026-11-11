using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Scheduler;

public enum Lifetime : uint
{
    Persistent = 0,
    Phase = 1,
    UntilRead = 2,
}
