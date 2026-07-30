using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_vertex_format : uint
{
    KE_GPU_VERTEX_FORMAT_FLOAT32X2,
    KE_GPU_VERTEX_FORMAT_FLOAT32X3,
    KE_GPU_VERTEX_FORMAT_FLOAT32X4,
    KE_GPU_VERTEX_FORMAT_SINT16X2,
    KE_GPU_VERTEX_FORMAT_SINT16X4,
    KE_GPU_VERTEX_FORMAT_UINT8X4_UNORM,
    KE_GPU_VERTEX_FORMAT_UINT8X4,
}
