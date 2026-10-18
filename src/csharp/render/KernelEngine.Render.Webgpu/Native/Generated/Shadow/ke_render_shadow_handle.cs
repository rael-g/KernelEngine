using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_shadow_handle
{
    public ke_render_shadow* @ref;

    [NativeTypeName("void (*)(ke_render_shadow *)")]
    public delegate* unmanaged[Cdecl]<ke_render_shadow*, void> destroy;
}
