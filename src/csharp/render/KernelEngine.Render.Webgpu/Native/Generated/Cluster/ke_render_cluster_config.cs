using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_render_cluster_config
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
