using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_binding_type : uint
{
    KE_GPU_BINDING_TYPE_BUFFER,
    KE_GPU_BINDING_TYPE_SAMPLER,
    KE_GPU_BINDING_TYPE_TEXTURE,
    KE_GPU_BINDING_TYPE_STORAGE_BUFFER,
    KE_GPU_BINDING_TYPE_STORAGE_TEXTURE,
    KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER,
    KE_GPU_BINDING_TYPE_DEPTH_TEXTURE,
}
