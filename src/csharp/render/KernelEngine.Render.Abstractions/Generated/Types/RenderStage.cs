using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum RenderStage : uint
{
    Prepass = 0,
    Opaque = 1,
    Sky = 2,
    Transparent = 3,
    HdrPost = 4,
    Tonemap = 5,
    LdrPost = 6,
    Overlay = 7,
    Count = 8,
}
