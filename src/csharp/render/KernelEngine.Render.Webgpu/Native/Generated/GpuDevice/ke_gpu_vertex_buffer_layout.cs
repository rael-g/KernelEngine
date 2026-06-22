using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_vertex_buffer_layout
{
    [NativeTypeName("uint64_t")]
    public ulong stride;

    public ke_gpu_vertex_step_mode step_mode;

    [NativeTypeName("uint32_t")]
    public uint attribute_count;

    [NativeTypeName("const ke_gpu_vertex_attribute *")]
    public ke_gpu_vertex_attribute* attributes;
}
