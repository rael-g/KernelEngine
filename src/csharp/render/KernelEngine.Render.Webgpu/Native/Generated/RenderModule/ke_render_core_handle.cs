using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_core_handle
{
    public ke_render_core* @ref;

    [NativeTypeName("void (*)(ke_render_core *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, void> destroy;
}
