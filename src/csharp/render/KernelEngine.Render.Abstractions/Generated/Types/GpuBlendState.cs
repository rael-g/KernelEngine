using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct GpuBlendState
{
    public bool BlendEnabled;
    public GpuBlendFactor SrcColor;
    public GpuBlendFactor DstColor;
    public GpuBlendOp ColorOp;
    public GpuBlendFactor SrcAlpha;
    public GpuBlendFactor DstAlpha;
    public GpuBlendOp AlphaOp;
    public byte WriteMask;
}
