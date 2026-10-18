using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_tonemap_handle
{
    public ke_render_tonemap* @ref;

    [NativeTypeName("void (*)(ke_render_tonemap *)")]
    public delegate* unmanaged[Cdecl]<ke_render_tonemap*, void> destroy;
}
