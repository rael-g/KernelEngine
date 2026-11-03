using System.Numerics;

using KernelEngine.Configuration.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_render_target_webgpu_window_params
{
    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("struct ke_window *")]
    public KernelEngine.Window.Native.ke_window* window;

    [NativeTypeName("ke_gpu_present_mode")]
    public GpuPresentMode present_mode;

    [NativeTypeName("ke_configuration *")]
    public KernelEngine.Configuration.Native.ke_configuration* configuration;
}
