using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuSamplerMipmapFilter : uint
{
    Nearest,
    Linear,
}
