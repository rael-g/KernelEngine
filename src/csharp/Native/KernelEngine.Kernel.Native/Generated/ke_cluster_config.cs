namespace KernelEngine.Kernel.Native;

public partial struct ke_cluster_config
{
    [NativeTypeName("uint32_t")]
    public uint grid_x;

    [NativeTypeName("uint32_t")]
    public uint grid_y;

    [NativeTypeName("uint32_t")]
    public uint grid_z;

    [NativeTypeName("uint32_t")]
    public uint max_lights_per_cluster;

    [NativeTypeName("uint32_t")]
    public uint max_total_lights;
}
