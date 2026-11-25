using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.RenderGraph;

public enum RenderGraphQueue : uint
{
    Graphics = 0,
    AsyncCompute = 1,
    Transfer = 2,
}
