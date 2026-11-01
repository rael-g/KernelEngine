using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum AlphaMode : uint
{
    Opaque,
    Mask,
    Blend,
}
