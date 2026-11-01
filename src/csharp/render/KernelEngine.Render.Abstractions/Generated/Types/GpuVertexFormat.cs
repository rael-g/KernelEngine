using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuVertexFormat : uint
{
    Float32x2,
    Float32x3,
    Float32x4,
    Sint16x2,
    Sint16x4,
    Uint8x4Unorm,
    Uint8x4,
}
