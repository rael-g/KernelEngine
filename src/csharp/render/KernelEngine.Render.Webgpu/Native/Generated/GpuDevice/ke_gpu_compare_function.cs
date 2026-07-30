using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_compare_function : uint
{
    KE_GPU_COMPARE_UNDEFINED = 0,
    KE_GPU_COMPARE_NEVER,
    KE_GPU_COMPARE_LESS,
    KE_GPU_COMPARE_EQUAL,
    KE_GPU_COMPARE_LESS_EQUAL,
    KE_GPU_COMPARE_GREATER,
    KE_GPU_COMPARE_NOT_EQUAL,
    KE_GPU_COMPARE_GREATER_EQUAL,
    KE_GPU_COMPARE_ALWAYS,
}
