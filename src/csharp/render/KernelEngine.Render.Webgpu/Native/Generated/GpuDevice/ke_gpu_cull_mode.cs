using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_cull_mode : uint
{
    KE_GPU_CULL_MODE_NONE,
    KE_GPU_CULL_MODE_FRONT,
    KE_GPU_CULL_MODE_BACK,
}
