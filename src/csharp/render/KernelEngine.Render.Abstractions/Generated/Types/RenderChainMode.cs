using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum RenderChainMode : uint
{
    DrawOver = 0,
    SampleOver = 1,
    Replace = 2,
}
