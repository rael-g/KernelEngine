using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_load_op : uint
{
    KE_GPU_LOAD_OP_LOAD,
    KE_GPU_LOAD_OP_CLEAR,
    KE_GPU_LOAD_OP_DONT_CARE,
}
