using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_vertex_attribute
{
    [NativeTypeName("uint32_t")]
    public uint shader_location;

    public ke_gpu_vertex_format format;

    [NativeTypeName("uint64_t")]
    public ulong offset;
}
