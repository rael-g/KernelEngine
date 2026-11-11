using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Scheduler;

public partial struct SystemOrder
{
    public ulong Id;
    public uint Wave;

    public bool Culled;
}
