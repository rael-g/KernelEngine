using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_device_webgpu_params
{
    public bool enable_validation;

    [NativeTypeName("struct ke_scheduler *")]
    public KernelEngine.Scheduler.Native.ke_scheduler* scheduler;

    public bool debug_labels;
}
