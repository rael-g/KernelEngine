using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuAddressMode : uint
{
    Repeat,
    MirroredRepeat,
    ClampToEdge,
    ClampToBorder,
}
