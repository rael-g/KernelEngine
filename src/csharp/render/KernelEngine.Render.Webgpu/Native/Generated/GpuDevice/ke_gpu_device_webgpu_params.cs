using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Configuration.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_device_webgpu_params
{
    public bool enable_validation;

    [NativeTypeName("struct ke_task_pool *")]
    public KernelEngine.TaskPool.Native.ke_task_pool* task_pool;

    public bool debug_labels;

    [NativeTypeName("ke_configuration *")]
    public KernelEngine.Configuration.Native.ke_configuration* configuration;
}
