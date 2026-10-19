using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_render_scene_component_ids
{
    [NativeTypeName("ke_component_id")]
    public uint mesh;

    [NativeTypeName("ke_component_id")]
    public uint camera;

    [NativeTypeName("ke_component_id")]
    public uint directional_light;

    [NativeTypeName("ke_component_id")]
    public uint point_light;

    [NativeTypeName("ke_component_id")]
    public uint spot_light;

    [NativeTypeName("ke_component_id")]
    public uint ambient_light;

    [NativeTypeName("ke_component_id")]
    public uint skybox;

    [NativeTypeName("ke_component_id")]
    public uint sprite2d;

    [NativeTypeName("ke_component_id")]
    public uint label;

    [NativeTypeName("ke_component_id")]
    public uint world_transform;
}
