using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_shadow_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("ke_view_space *")]
    public KernelEngine.View.Native.ke_view_space* view_space;

    [NativeTypeName("ke_ndc_convention")]
    public KernelEngine.View.Native.ke_ndc_convention ndc;

    [NativeTypeName("ke_component_id")]
    public uint mesh_cid;

    [NativeTypeName("ke_component_id")]
    public uint world_transform_cid;

    [NativeTypeName("ke_component_id")]
    public uint light_cid;

    [NativeTypeName("ke_component_id")]
    public uint frame_cid;

    [NativeTypeName("const char *")]
    public sbyte* output;

    [NativeTypeName("uint32_t")]
    public uint resolution;

    public float light_distance;

    public float extent;

    public float near_plane;

    public float far_plane;
}
