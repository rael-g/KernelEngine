using KernelEngine.Kernel.Native;

namespace KernelEngine.Threading.Native;

public partial struct ke_frame_shadow
{
    [NativeTypeName("uint32_t")]
    public uint map_handle;

    public ke_mat4 light_view;

    public ke_mat4 light_proj;
}
