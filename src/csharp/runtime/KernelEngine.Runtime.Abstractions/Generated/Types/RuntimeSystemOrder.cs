using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Runtime;

public partial struct RuntimeSystemOrder
{
    public ulong Id;
    public uint Wave;

    public bool Culled;
}
