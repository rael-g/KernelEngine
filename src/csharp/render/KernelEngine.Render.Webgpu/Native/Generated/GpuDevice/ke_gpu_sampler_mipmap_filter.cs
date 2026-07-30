using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_sampler_mipmap_filter : uint
{
    KE_GPU_SAMPLER_MIPMAP_NEAREST,
    KE_GPU_SAMPLER_MIPMAP_LINEAR,
}
