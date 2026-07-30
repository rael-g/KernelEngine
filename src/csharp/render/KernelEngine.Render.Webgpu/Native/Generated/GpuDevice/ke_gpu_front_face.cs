using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_front_face : uint
{
    KE_GPU_FRONT_FACE_CCW,
    KE_GPU_FRONT_FACE_CW,
}
