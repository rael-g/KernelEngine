using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

/// <summary>Configuration for the Clustered Forward Shading grid.</summary>
[StructLayout(LayoutKind.Sequential)]
public partial struct ke_cluster_config
{
    public uint grid_x;
    public uint grid_y;
    public uint grid_z;
    public uint max_lights_per_cluster;
    public uint max_total_lights;
}
