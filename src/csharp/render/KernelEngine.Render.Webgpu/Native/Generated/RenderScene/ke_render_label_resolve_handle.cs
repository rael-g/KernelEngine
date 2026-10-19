using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_label_resolve_handle
{
    public ke_render_label_resolve* @ref;

    [NativeTypeName("void (*)(ke_render_label_resolve *)")]
    public delegate* unmanaged[Cdecl]<ke_render_label_resolve*, void> destroy;
}
