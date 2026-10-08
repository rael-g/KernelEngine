using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_render_target_handle
{
    public ke_gpu_render_target* @ref;

    [NativeTypeName("void (*)(ke_gpu_render_target *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, void> destroy;
}
