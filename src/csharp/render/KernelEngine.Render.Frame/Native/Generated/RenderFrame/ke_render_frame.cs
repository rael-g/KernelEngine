using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.RenderGraph.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Frame.Native;

public unsafe partial struct ke_render_frame
{
    public void* handle;

    [NativeTypeName("ke_component_id (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, global::KernelEngine.Ecs.ComponentId> frame_cid;

    [NativeTypeName("ke_render_graph *(*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, KernelEngine.RenderGraph.Native.ke_render_graph*> graph;

    [NativeTypeName("bool (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, bool> live;

    [NativeTypeName("ke_render_graph_resource (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, global::KernelEngine.RenderGraph.RenderGraphResource> color;

    [NativeTypeName("ke_render_graph_resource (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, global::KernelEngine.RenderGraph.RenderGraphResource> depth;

    [NativeTypeName("ke_render_graph_resource (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, global::KernelEngine.RenderGraph.RenderGraphResource> output;

    [NativeTypeName("void (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, void> claim_output;

    [NativeTypeName("ke_result (*)(struct ke_render_frame *, const char *, ke_render_graph_resource)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, sbyte*, global::KernelEngine.RenderGraph.RenderGraphResource, KernelEngine.Result.Native.Result> publish;

    [NativeTypeName("ke_render_graph_resource (*)(struct ke_render_frame *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, sbyte*, global::KernelEngine.RenderGraph.RenderGraphResource> find;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, global::KernelEngine.Render.GpuTextureFormat> color_format;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, global::KernelEngine.Render.GpuTextureFormat> depth_format;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, global::KernelEngine.Render.GpuTextureFormat> output_format;
}
