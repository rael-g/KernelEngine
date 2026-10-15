using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_shader_binding
{
    [NativeTypeName("const char *")]
    public sbyte* name;

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
