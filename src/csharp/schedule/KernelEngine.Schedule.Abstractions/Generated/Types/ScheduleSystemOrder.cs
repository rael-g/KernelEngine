using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Schedule;

public partial struct ScheduleSystemOrder
{
    public ulong Id;
    public uint Wave;

    public bool Ambiguous;
}
