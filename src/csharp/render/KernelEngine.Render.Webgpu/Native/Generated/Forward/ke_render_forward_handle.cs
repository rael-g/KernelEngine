using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_forward_handle
{
    public ke_render_forward* @ref;

    [NativeTypeName("void (*)(ke_render_forward *)")]
    public delegate* unmanaged[Cdecl]<ke_render_forward*, void> destroy;
}
