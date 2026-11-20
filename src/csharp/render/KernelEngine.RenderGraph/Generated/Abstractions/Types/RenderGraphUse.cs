using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.RenderGraph;

public partial struct RenderGraphUse
{
    public global::KernelEngine.RenderGraph.RenderGraphResource Resource;
    public RenderGraphUsage Usage;
    public uint BaseMip;
    public uint MipCount;
    public uint BaseLayer;
    public uint LayerCount;
    public global::KernelEngine.Render.GpuTextureFormat ViewFormat;
    public RenderGraphLoad Load;
    public _ClearColor_e__FixedBuffer ClearColor;

    public float ClearDepth;
    public uint ClearStencil;

    [InlineArray(4)]
    public partial struct _ClearColor_e__FixedBuffer
    {
        public float e0;
    }
}
