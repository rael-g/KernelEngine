using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_index_format : uint
{
    KE_GPU_INDEX_FORMAT_UINT16,
    KE_GPU_INDEX_FORMAT_UINT32,
}
