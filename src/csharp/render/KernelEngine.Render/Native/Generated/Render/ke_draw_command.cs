using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_draw_command
{
    public ke_mesh_handle mesh_handle;

    public ke_material_handle material_handle;

    public ke_mat4 transform;
}
