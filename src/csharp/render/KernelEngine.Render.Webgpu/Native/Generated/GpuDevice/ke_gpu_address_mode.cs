using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public enum ke_gpu_address_mode
{
    KE_GPU_ADDRESS_MODE_REPEAT,
    KE_GPU_ADDRESS_MODE_MIRRORED_REPEAT,
    KE_GPU_ADDRESS_MODE_CLAMP_TO_EDGE,
    KE_GPU_ADDRESS_MODE_CLAMP_TO_BORDER,
}
