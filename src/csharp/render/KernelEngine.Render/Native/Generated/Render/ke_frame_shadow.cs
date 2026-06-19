using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_frame_shadow
{
    public ke_shadow_map_handle map_handle;

    public ke_mat4 light_view;

    public ke_mat4 light_proj;
}
