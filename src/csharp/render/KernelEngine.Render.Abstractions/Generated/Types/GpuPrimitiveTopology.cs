using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuPrimitiveTopology : uint
{
    TriangleList,
    TriangleStrip,
    LineList,
    LineStrip,
    PointList,
}
