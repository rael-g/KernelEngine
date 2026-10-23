using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_frame
{
    public void* handle;

    [NativeTypeName("ke_component_id (*)(struct ke_render_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_render_frame*, uint> frame_cid;
}
