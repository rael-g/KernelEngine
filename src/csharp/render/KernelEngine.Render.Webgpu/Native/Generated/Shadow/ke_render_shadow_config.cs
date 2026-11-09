using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_render_shadow_config
{
    [NativeTypeName("uint32_t")]
    public uint resolution;

    public float light_distance;

    public float extent;

    public float near_plane;

    public float far_plane;
}
