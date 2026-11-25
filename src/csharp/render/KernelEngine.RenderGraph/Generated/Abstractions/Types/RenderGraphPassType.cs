using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.RenderGraph;

public enum RenderGraphPassType : uint
{
    Raster = 0,
    Compute = 1,
    Copy = 2,
}
