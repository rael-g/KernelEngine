using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_bind_group_params
{
    [NativeTypeName("ke_gpu_bind_group_layout")]
    public ulong layout;

    [NativeTypeName("uint32_t")]
    public uint entry_count;

    [NativeTypeName("const ke_gpu_bind_group_entry *")]
    public ke_gpu_bind_group_entry* entries;
}
