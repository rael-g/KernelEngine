using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_store_op : uint
{
    KE_GPU_STORE_OP_STORE,
    KE_GPU_STORE_OP_DONT_CARE,
}
