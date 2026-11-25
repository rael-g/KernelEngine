using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_assets_handle
{
    public ke_render_assets* @ref;

    [NativeTypeName("void (*)(ke_render_assets *)")]
    public delegate* unmanaged[Cdecl]<ke_render_assets*, void> destroy;
}
