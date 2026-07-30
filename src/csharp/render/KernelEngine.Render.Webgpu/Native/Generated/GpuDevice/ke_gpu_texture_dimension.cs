using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_texture_dimension : uint
{
    KE_GPU_TEXTURE_DIM_1D,
    KE_GPU_TEXTURE_DIM_2D,
    KE_GPU_TEXTURE_DIM_3D,
    KE_GPU_TEXTURE_DIM_CUBE,
}
