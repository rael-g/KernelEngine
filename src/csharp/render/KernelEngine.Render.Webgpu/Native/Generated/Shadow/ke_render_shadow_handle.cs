using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_shadow_handle
{
    public ke_render_shadow* @ref;

    [NativeTypeName("void (*)(ke_render_shadow *)")]
    public delegate* unmanaged[Cdecl]<ke_render_shadow*, void> destroy;
}
