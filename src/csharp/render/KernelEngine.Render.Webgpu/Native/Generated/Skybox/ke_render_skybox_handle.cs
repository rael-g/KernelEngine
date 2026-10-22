using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_skybox_handle
{
    public ke_render_skybox* @ref;

    [NativeTypeName("void (*)(ke_render_skybox *)")]
    public delegate* unmanaged[Cdecl]<ke_render_skybox*, void> destroy;
}
