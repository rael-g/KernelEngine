using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum RenderDepthMode : uint
{
    None = 0,
    Test = 1,
    Write = 2,
}
