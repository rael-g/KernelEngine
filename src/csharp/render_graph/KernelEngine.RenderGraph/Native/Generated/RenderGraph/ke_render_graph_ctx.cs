using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Completion.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.RenderGraph.Native;

public unsafe partial struct ke_render_graph_ctx
{
    public void* handle;

    [NativeTypeName("ke_gpu_command_encoder *(*)(ke_render_graph_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph_ctx*, KernelEngine.Render.Native.ke_gpu_command_encoder*> encoder;

    [NativeTypeName("ke_gpu_render_pass *(*)(ke_render_graph_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph_ctx*, KernelEngine.Render.Native.ke_gpu_render_pass*> render_pass;

    [NativeTypeName("ke_gpu_compute_pass *(*)(ke_render_graph_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph_ctx*, KernelEngine.Render.Native.ke_gpu_compute_pass*> compute_pass;

    [NativeTypeName("ke_gpu_texture (*)(ke_render_graph_ctx *, ke_render_graph_resource)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph_ctx*, global::KernelEngine.RenderGraph.RenderGraphResource, ulong> texture;

    [NativeTypeName("ke_gpu_texture_view (*)(ke_render_graph_ctx *, ke_render_graph_resource)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph_ctx*, global::KernelEngine.RenderGraph.RenderGraphResource, ulong> texture_view;

    [NativeTypeName("ke_gpu_buffer (*)(ke_render_graph_ctx *, ke_render_graph_resource)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph_ctx*, global::KernelEngine.RenderGraph.RenderGraphResource, ulong> buffer;
}
