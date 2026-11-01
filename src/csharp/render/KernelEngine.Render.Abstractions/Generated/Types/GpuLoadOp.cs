using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuLoadOp : uint
{
    Load,
    Clear,
    DontCare,
}
