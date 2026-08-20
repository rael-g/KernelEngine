using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_render_shadow_params
{
    [NativeTypeName("uint32_t")]
    public uint resolution;

    public float light_distance;

    public float extent;

    public float near_plane;

    public float far_plane;
}
