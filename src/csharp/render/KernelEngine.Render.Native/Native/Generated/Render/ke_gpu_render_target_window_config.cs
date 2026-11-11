using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_gpu_render_target_window_config
{
    [NativeTypeName("ke_gpu_present_mode")]
    public global::KernelEngine.Render.GpuPresentMode present_mode;
}
