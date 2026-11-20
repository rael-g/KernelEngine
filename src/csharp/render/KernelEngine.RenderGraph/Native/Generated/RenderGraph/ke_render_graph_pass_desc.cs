using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Completion.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.RenderGraph.Native;

public unsafe partial struct ke_render_graph_pass_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("ke_render_graph_pass_type")]
    public global::KernelEngine.RenderGraph.RenderGraphPassType type;

    [NativeTypeName("ke_render_graph_queue")]
    public global::KernelEngine.RenderGraph.RenderGraphQueue queue;

    [NativeTypeName("uint32_t")]
    public uint injection_point;

    public bool side_effect;

    [NativeTypeName("const ke_render_graph_use *")]
    public global::KernelEngine.RenderGraph.RenderGraphUse* uses;

    [NativeTypeName("uint32_t")]
    public uint use_count;

    [NativeTypeName("ke_render_graph_record_fn")]
    public delegate* unmanaged[Cdecl]<void*, ke_render_graph_ctx*, KernelEngine.Result.Native.Result> record;

    [NativeTypeName("ke_render_graph_condition_fn")]
    public delegate* unmanaged[Cdecl]<void*, bool> condition;

    [NativeTypeName("ke_render_graph_readback_fn")]
    public delegate* unmanaged[Cdecl]<void*, global::KernelEngine.RenderGraph.RenderGraphResource, void*, nuint, void> readback;

    public void* user;
}
