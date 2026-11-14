using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Completion.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.RenderGraph.Native;

public unsafe partial struct ke_render_graph_texture_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat format;

    [NativeTypeName("ke_render_graph_size_class")]
    public global::KernelEngine.RenderGraph.RenderGraphSizeClass size_class;

    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    public float scale_x;

    public float scale_y;

    [NativeTypeName("ke_render_graph_resource")]
    public global::KernelEngine.RenderGraph.RenderGraphResource relative_to;

    [NativeTypeName("uint32_t")]
    public uint mip_levels;

    [NativeTypeName("uint32_t")]
    public uint array_layers;

    [NativeTypeName("uint32_t")]
    public uint samples;

    public bool generate_mips;
}
