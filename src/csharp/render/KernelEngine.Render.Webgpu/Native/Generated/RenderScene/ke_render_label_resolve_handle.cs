using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_label_resolve_handle
{
    public ke_render_label_resolve* @ref;

    [NativeTypeName("void (*)(ke_render_label_resolve *)")]
    public delegate* unmanaged[Cdecl]<ke_render_label_resolve*, void> destroy;
}
