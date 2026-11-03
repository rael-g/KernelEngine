using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct GpuDepthStencilState
{
    public bool DepthTestEnabled;

    public bool DepthWriteEnabled;
    public GpuCompareFunction DepthCompare;

    public bool StencilTestEnabled;
    public GpuStencilOp StencilFrontFail;
    public GpuStencilOp StencilFrontDepthFail;
    public GpuStencilOp StencilFrontPass;
    public GpuCompareFunction StencilFrontCompare;
    public GpuStencilOp StencilBackFail;
    public GpuStencilOp StencilBackDepthFail;
    public GpuStencilOp StencilBackPass;
    public GpuCompareFunction StencilBackCompare;
    public byte StencilReadMask;
    public byte StencilWriteMask;
}
