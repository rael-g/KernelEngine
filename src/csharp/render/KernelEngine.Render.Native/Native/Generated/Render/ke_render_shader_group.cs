using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_render_shader_group
{
    [NativeTypeName("ke_gpu_bind_group_layout")]
    public ulong layout;

    [NativeTypeName("uint32_t")]
    public uint index;
}
