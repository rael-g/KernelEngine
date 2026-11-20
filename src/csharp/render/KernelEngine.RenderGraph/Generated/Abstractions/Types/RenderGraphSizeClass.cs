using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.RenderGraph;

public enum RenderGraphSizeClass : uint
{
    Absolute = 0,
    OutputRelative = 1,
    ResourceRelative = 2,
}
