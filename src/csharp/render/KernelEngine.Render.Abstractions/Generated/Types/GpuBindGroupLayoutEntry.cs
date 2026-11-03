using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct GpuBindGroupLayoutEntry
{
    public uint Binding;
    public uint Visibility;
    public GpuBindingType Type;

    public bool HasDynamicOffset;
    public GpuTextureDimension ViewDimension;
}
