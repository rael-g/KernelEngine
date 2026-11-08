using System.Numerics;

using KernelEngine.Configuration.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_render_target_webgpu_window_config
{
    [NativeTypeName("ke_gpu_present_mode")]
    public GpuPresentMode present_mode;
}
