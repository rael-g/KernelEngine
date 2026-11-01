using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum RenderSizeMode : uint
{
    Absolute = 0,
    RelativeToBackbuffer = 1,
}
