using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_graph_handle
{
    public ke_render_graph* @ref;

    [NativeTypeName("void (*)(ke_render_graph *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, void> destroy;
}
