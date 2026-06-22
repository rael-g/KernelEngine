using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_device_webgpu_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;

    [NativeTypeName("struct ke_window *")]
    public KernelEngine.Window.Native.ke_window* window;

    [NativeTypeName("ke_bool")]
    public byte enable_validation;
}
