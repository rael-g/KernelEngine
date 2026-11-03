using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct GpuDepthStencilAttachment
{
    public ulong View;
    public GpuLoadOp DepthLoadOp;
    public GpuStoreOp DepthStoreOp;
    public GpuStoreOp StencilStoreOp;

    public float ClearDepth;
    public byte ClearStencil;

    public bool DepthReadOnly;

    public bool StencilReadOnly;
}
