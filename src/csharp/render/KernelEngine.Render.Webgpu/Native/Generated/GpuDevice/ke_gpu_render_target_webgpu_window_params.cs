using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_render_target_webgpu_window_params
{
    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("struct ke_window *")]
    public KernelEngine.Window.Native.ke_window* window;

    public ke_gpu_present_mode present_mode;
}
