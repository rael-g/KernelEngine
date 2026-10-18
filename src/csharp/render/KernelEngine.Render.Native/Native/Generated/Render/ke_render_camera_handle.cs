using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_camera_handle
{
    public ke_render_camera* @ref;

    [NativeTypeName("void (*)(ke_render_camera *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, void> destroy;
}
