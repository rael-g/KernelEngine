using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_frame_handle
{
    public ke_render_frame* @ref;

    [NativeTypeName("void (*)(ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, void> destroy;
}
