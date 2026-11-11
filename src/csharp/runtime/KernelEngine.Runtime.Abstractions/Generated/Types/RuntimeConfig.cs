using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Runtime;

public partial struct RuntimeConfig
{
    public float FixedDt;

    public float FixedDtMaxAccum;
    public uint MaxSystemsPerPhase;
}
