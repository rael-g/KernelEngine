using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_deferred_lighting_handle
{
    public ke_render_deferred_lighting* @ref;

    [NativeTypeName("void (*)(ke_render_deferred_lighting *)")]
    public delegate* unmanaged[Cdecl]<ke_render_deferred_lighting*, void> destroy;
}
