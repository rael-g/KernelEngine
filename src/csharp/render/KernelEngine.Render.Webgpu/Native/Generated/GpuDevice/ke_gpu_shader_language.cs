using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_shader_language : uint
{
    KE_GPU_SHADER_LANG_WGSL = 0,
    KE_GPU_SHADER_LANG_SPIRV = 1,
    KE_GPU_SHADER_LANG_MSL = 2,
    KE_GPU_SHADER_LANG_DXIL = 3,
}
