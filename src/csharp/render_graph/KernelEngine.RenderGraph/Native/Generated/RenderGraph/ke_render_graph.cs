using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Completion.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.RenderGraph.Native;

public unsafe partial struct ke_render_graph
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_render_graph *, uint32_t, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, uint, uint, KernelEngine.Result.Native.Result> begin_frame;

    [NativeTypeName("ke_result (*)(ke_render_graph *, const ke_render_graph_texture_desc *, ke_render_graph_resource *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_render_graph_texture_desc*, global::KernelEngine.RenderGraph.RenderGraphResource*, KernelEngine.Result.Native.Result> create_texture;

    [NativeTypeName("ke_result (*)(ke_render_graph *, const ke_render_graph_buffer_desc *, ke_render_graph_resource *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_render_graph_buffer_desc*, global::KernelEngine.RenderGraph.RenderGraphResource*, KernelEngine.Result.Native.Result> create_buffer;

    [NativeTypeName("ke_result (*)(ke_render_graph *, const char *, ke_render_graph_resource *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, global::KernelEngine.RenderGraph.RenderGraphResource*, KernelEngine.Result.Native.Result> create_token;

    [NativeTypeName("ke_result (*)(ke_render_graph *, ke_gpu_texture, ke_gpu_texture_view, ke_gpu_texture_format, uint32_t, uint32_t, ke_render_graph_usage, ke_render_graph_resource *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ulong, ulong, global::KernelEngine.Render.GpuTextureFormat, uint, uint, global::KernelEngine.RenderGraph.RenderGraphUsage, global::KernelEngine.RenderGraph.RenderGraphResource*, KernelEngine.Result.Native.Result> import_texture;

    [NativeTypeName("ke_result (*)(ke_render_graph *, ke_gpu_buffer, uint64_t, ke_render_graph_resource *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ulong, ulong, global::KernelEngine.RenderGraph.RenderGraphResource*, KernelEngine.Result.Native.Result> import_buffer;

    [NativeTypeName("ke_result (*)(ke_render_graph *, ke_render_graph_resource, ke_render_graph_export *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, global::KernelEngine.RenderGraph.RenderGraphResource, global::KernelEngine.RenderGraph.RenderGraphExport*, KernelEngine.Result.Native.Result> export_resource;

    [NativeTypeName("ke_result (*)(ke_render_graph *, ke_render_graph_export, ke_render_graph_resource *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, global::KernelEngine.RenderGraph.RenderGraphExport, global::KernelEngine.RenderGraph.RenderGraphResource*, KernelEngine.Result.Native.Result> import_export;

    [NativeTypeName("void (*)(ke_render_graph *, ke_render_graph_export)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, global::KernelEngine.RenderGraph.RenderGraphExport, void> release_export;

    [NativeTypeName("ke_result (*)(ke_render_graph *, const ke_render_graph_pass_desc *, ke_render_graph_pass *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_render_graph_pass_desc*, global::KernelEngine.RenderGraph.RenderGraphPass*, KernelEngine.Result.Native.Result> add_pass;

    [NativeTypeName("ke_result (*)(ke_render_graph *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, KernelEngine.Result.Native.Result> compile;

    [NativeTypeName("ke_result (*)(ke_render_graph *, ke_completion **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result> execute;
}
