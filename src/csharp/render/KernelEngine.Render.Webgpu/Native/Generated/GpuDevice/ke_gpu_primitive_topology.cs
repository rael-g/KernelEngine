using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_gpu_primitive_topology : uint
{
    KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
    KE_GPU_PRIMITIVE_TOPOLOGY_LINE_LIST,
    KE_GPU_PRIMITIVE_TOPOLOGY_LINE_STRIP,
    KE_GPU_PRIMITIVE_TOPOLOGY_POINT_LIST,
}
