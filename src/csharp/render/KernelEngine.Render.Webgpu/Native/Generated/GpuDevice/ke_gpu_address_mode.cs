using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_address_mode : uint
{
    KE_GPU_ADDRESS_MODE_REPEAT,
    KE_GPU_ADDRESS_MODE_MIRRORED_REPEAT,
    KE_GPU_ADDRESS_MODE_CLAMP_TO_EDGE,
    KE_GPU_ADDRESS_MODE_CLAMP_TO_BORDER,
}
