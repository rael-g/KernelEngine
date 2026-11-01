using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct GpuBindGroupEntry
{
    public uint Binding;
    public GpuBindingType Type;
    public ulong Buffer;
    public ulong BufferOffset;
    public ulong BufferSize;
    public ulong TextureView;
    public ulong Sampler;
}
