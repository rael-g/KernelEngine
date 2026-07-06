using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_render_cluster_params
{
    [NativeTypeName("uint32_t")]
    public uint grid_x;

    [NativeTypeName("uint32_t")]
    public uint grid_y;

    [NativeTypeName("uint32_t")]
    public uint grid_z;

    [NativeTypeName("uint32_t")]
    public uint max_lights_per_cluster;
}
