using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_device_webgpu_params
{
    public bool enable_validation;

    [NativeTypeName("struct ke_task_pool *")]
    public KernelEngine.TaskPool.Native.ke_task_pool* task_pool;

    public bool debug_labels;
}
