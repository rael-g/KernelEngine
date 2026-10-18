using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_camera_frustum
{
    public float tan_half_fov_y;

    public float aspect;

    public float near_plane;

    public float far_plane;
}
