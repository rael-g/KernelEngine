using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_device_webgpu_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;

    public bool enable_validation;

    [NativeTypeName("struct ke_scheduler *")]
    public KernelEngine.Scheduler.Native.ke_scheduler* scheduler;

    public bool debug_labels;
}
