using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_frame
{
    public void* handle;

    [NativeTypeName("ke_component_id (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, global::KernelEngine.Ecs.ComponentId> frame_cid;
}
