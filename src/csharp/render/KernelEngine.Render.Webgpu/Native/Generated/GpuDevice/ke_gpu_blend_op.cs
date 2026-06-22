using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public enum ke_gpu_blend_op
{
    KE_GPU_BLEND_OP_ADD,
    KE_GPU_BLEND_OP_SUBTRACT,
    KE_GPU_BLEND_OP_REVERSE_SUBTRACT,
    KE_GPU_BLEND_OP_MIN,
    KE_GPU_BLEND_OP_MAX,
}
