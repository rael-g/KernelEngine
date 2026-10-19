using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_resource_binder_handle
{
    public ke_render_resource_binder* @ref;

    [NativeTypeName("void (*)(ke_render_resource_binder *)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, void> destroy;
}
