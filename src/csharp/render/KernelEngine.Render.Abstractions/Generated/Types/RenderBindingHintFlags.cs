using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum RenderBindingHintFlags : uint
{
    Depth = 0x1U,
    DynamicOffset = 0x2U,
}
