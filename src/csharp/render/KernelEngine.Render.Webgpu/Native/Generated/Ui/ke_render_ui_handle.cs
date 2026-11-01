using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;
using global::KernelEngine.Text;

using KernelEngine.Ecs.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_ui_handle
{
    public ke_render_ui* @ref;

    [NativeTypeName("void (*)(ke_render_ui *)")]
    public delegate* unmanaged[Cdecl]<ke_render_ui*, void> destroy;
}
