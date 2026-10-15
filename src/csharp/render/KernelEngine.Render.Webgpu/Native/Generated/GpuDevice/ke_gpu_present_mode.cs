using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_present_mode : uint
{
    KE_GPU_PRESENT_MODE_FIFO = 0,
    KE_GPU_PRESENT_MODE_MAILBOX = 1,
    KE_GPU_PRESENT_MODE_IMMEDIATE = 2,
}
