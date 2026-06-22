using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_bind_group_layout_params
{
    [NativeTypeName("uint32_t")]
    public uint entry_count;

    [NativeTypeName("const ke_gpu_bind_group_layout_entry *")]
    public ke_gpu_bind_group_layout_entry* entries;
}
