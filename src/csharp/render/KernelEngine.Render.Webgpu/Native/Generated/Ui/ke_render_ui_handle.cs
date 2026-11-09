using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;
using global::KernelEngine.Text;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_ui_handle
{
    public ke_render_ui* @ref;

    [NativeTypeName("void (*)(ke_render_ui *)")]
    public delegate* unmanaged[Cdecl]<ke_render_ui*, void> destroy;
}
