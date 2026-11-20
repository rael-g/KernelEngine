using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.Render.Frame;

public enum PartCardinality : uint
{
    One = 1,
    Optional = 2,
    Many = 3,
}
