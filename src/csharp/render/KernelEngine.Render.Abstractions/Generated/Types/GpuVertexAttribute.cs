using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct GpuVertexAttribute
{
    public uint ShaderLocation;
    public GpuVertexFormat Format;
    public ulong Offset;
}
