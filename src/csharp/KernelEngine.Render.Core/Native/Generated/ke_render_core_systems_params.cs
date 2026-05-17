using KernelEngine.Kernel.Native;

namespace KernelEngine.Render.Core.Native;

public partial struct ke_render_core_systems_params
{
    [NativeTypeName("uint32_t")]
    public uint mesh_cid;

    [NativeTypeName("uint32_t")]
    public uint transform_cid;

    [NativeTypeName("uint32_t")]
    public uint light_cid;

    [NativeTypeName("uint32_t")]
    public uint point_cid;

    [NativeTypeName("uint32_t")]
    public uint spot_cid;

    [NativeTypeName("uint32_t")]
    public uint camera_cid;

    [NativeTypeName("uint32_t")]
    public uint skybox_cid;
}
