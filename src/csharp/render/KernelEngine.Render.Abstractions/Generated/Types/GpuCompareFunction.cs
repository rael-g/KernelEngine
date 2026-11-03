using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuCompareFunction : uint
{
    Undefined = 0,
    Never,
    Less,
    Equal,
    LessEqual,
    Greater,
    NotEqual,
    GreaterEqual,
    Always,
}
