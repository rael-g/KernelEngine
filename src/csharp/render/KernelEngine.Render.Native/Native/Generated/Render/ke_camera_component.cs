using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_camera_component
{
    public float fov;

    public float near_plane;

    public float far_plane;

    public float orthographic_size;

    [NativeTypeName("uint8_t")]
    public byte orthographic;

    [NativeTypeName("uint32_t")]
    public uint cull_mask;
}
