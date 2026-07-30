using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_barrier_type : uint
{
    KE_GPU_BARRIER_BUFFER,
    KE_GPU_BARRIER_TEXTURE,
}
