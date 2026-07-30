using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_blend_op : uint
{
    KE_GPU_BLEND_OP_ADD,
    KE_GPU_BLEND_OP_SUBTRACT,
    KE_GPU_BLEND_OP_REVERSE_SUBTRACT,
    KE_GPU_BLEND_OP_MIN,
    KE_GPU_BLEND_OP_MAX,
}
