using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Part.Native;
using KernelEngine.RenderGraph.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Frame.Native;

public unsafe partial struct ke_render_frame_handle
{
    public ke_render_frame* @ref;

    [NativeTypeName("void (*)(ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, void> destroy;
}
