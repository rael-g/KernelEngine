using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuCullMode : uint
{
    None,
    Front,
    Back,
}
