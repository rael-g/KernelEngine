using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_filter : uint
{
    KE_GPU_FILTER_NEAREST,
    KE_GPU_FILTER_LINEAR,
}
