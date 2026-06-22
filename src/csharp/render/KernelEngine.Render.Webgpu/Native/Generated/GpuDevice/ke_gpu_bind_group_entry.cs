using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_bind_group_entry
{
    [NativeTypeName("uint32_t")]
    public uint binding;

    public ke_gpu_binding_type type;

    [NativeTypeName("ke_gpu_buffer")]
    public ulong buffer;

    [NativeTypeName("uint64_t")]
    public ulong buffer_offset;

    [NativeTypeName("uint64_t")]
    public ulong buffer_size;

    [NativeTypeName("ke_gpu_texture_view")]
    public ulong texture_view;

    [NativeTypeName("ke_gpu_sampler")]
    public ulong sampler;
}
