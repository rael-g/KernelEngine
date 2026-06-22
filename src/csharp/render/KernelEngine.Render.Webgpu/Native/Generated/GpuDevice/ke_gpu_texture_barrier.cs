using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_texture_barrier
{
    [NativeTypeName("ke_gpu_texture")]
    public ulong texture;

    [NativeTypeName("ke_gpu_texture_usage")]
    public uint from_state;

    [NativeTypeName("ke_gpu_texture_usage")]
    public uint to_state;
}
