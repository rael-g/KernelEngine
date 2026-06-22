using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_buffer_params
{
    [NativeTypeName("const void *")]
    public void* initial_data;

    [NativeTypeName("size_t")]
    public nuint size;

    [NativeTypeName("ke_gpu_buffer_usage")]
    public uint usage;

    [NativeTypeName("ke_bool")]
    public byte mapped_at_creation;
}
