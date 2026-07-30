using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_vertex_step_mode : uint
{
    KE_GPU_VERTEX_STEP_MODE_VERTEX,
    KE_GPU_VERTEX_STEP_MODE_INSTANCE,
}
