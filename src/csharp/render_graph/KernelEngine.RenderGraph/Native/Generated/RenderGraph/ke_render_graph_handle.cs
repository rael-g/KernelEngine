using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Completion.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.RenderGraph.Native;

public unsafe partial struct ke_render_graph_handle
{
    public ke_render_graph* @ref;

    [NativeTypeName("void (*)(ke_render_graph *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, void> destroy;
}
