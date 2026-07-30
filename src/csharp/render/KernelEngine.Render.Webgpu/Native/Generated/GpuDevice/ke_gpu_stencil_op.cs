using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_stencil_op : uint
{
    KE_GPU_STENCIL_OP_KEEP,
    KE_GPU_STENCIL_OP_ZERO,
    KE_GPU_STENCIL_OP_REPLACE,
    KE_GPU_STENCIL_OP_INVERT,
    KE_GPU_STENCIL_OP_INCREMENT_CLAMP,
    KE_GPU_STENCIL_OP_DECREMENT_CLAMP,
}
