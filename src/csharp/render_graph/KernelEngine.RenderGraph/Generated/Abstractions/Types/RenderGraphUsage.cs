using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.RenderGraph;

public enum RenderGraphUsage : uint
{
    Sampled = 0,
    StorageRead = 1,
    StorageWrite = 2,
    ColorAttachment = 3,
    DepthRead = 4,
    DepthWrite = 5,
    InputAttachment = 6,
    Resolve = 7,
    CopySrc = 8,
    CopyDst = 9,
    Vertex = 10,
    Index = 11,
    Indirect = 12,
    Uniform = 13,
    Present = 14,
    Readback = 15,
    AsBuild = 16,
    AsRead = 17,
    TokenRead = 18,
    TokenWrite = 19,
}
