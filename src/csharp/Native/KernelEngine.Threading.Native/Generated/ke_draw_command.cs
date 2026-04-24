using KernelEngine.Kernel.Native;

namespace KernelEngine.Threading.Native;

public partial struct ke_draw_command
{
    [NativeTypeName("uint32_t")]
    public uint mesh_handle;

    [NativeTypeName("uint32_t")]
    public uint material_handle;

    public ke_mat4 transform;
}
