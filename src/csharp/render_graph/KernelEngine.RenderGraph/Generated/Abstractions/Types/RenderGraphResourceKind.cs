using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.RenderGraph;

public enum RenderGraphResourceKind : uint
{
    Texture = 0,
    Buffer = 1,
    Token = 2,
    AccelerationStructure = 3,
}
