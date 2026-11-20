using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.RenderGraph;

public enum RenderGraphLoad : uint
{
    Keep = 0,
    Clear = 1,
    DontCare = 2,
}
