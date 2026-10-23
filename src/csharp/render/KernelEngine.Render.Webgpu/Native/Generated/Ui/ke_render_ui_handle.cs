using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_ui_handle
{
    public ke_render_ui* @ref;

    [NativeTypeName("void (*)(ke_render_ui *)")]
    public delegate* unmanaged[Cdecl]<ke_render_ui*, void> destroy;
}
