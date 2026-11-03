using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuBlendOp : uint
{
    Add,
    Subtract,
    ReverseSubtract,
    Min,
    Max,
}
