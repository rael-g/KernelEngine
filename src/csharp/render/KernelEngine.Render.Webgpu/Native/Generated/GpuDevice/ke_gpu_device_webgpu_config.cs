using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_device_webgpu_config
{
    public bool enable_validation;

    public bool debug_labels;
}
