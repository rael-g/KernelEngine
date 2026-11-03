using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_forward_handle
{
    public ke_render_forward* @ref;

    [NativeTypeName("void (*)(ke_render_forward *)")]
    public delegate* unmanaged[Cdecl]<ke_render_forward*, void> destroy;
}
