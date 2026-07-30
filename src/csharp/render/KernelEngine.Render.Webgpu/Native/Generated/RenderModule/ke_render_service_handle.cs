using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_service_handle
{
    public ke_render_service* @ref;

    [NativeTypeName("void (*)(ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, void> destroy;
}
