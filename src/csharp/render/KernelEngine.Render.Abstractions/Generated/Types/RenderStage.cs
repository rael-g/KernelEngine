using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum RenderStage : uint
{
    Opaque = 0,
    Sky = 1,
    Transparent = 2,
    HdrPost = 3,
    Tonemap = 4,
    LdrPost = 5,
    Overlay = 6,
    Count = 7,
}
