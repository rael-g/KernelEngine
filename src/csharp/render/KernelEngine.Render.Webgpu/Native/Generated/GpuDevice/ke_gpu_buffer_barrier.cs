using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_buffer_barrier
{
    [NativeTypeName("ke_gpu_buffer")]
    public ulong buffer;

    [NativeTypeName("ke_gpu_buffer_usage")]
    public uint from_state;

    [NativeTypeName("ke_gpu_buffer_usage")]
    public uint to_state;
}
