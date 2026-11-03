using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuBlendFactor : uint
{
    Zero,
    One,
    SrcAlpha,
    OneMinusSrcAlpha,
    DstAlpha,
    OneMinusDstAlpha,
    SrcColor,
    OneMinusSrcColor,
    DstColor,
    OneMinusDstColor,
}
