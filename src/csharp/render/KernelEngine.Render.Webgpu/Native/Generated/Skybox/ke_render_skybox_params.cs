using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_skybox_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("ke_render_camera *")]
    public KernelEngine.Render.Native.ke_render_camera* camera;

    [NativeTypeName("ke_component_id")]
    public uint camera_cid;

    [NativeTypeName("ke_component_id")]
    public uint world_transform_cid;

    [NativeTypeName("ke_component_id")]
    public uint skybox_cid;

    [NativeTypeName("ke_component_id")]
    public uint frame_cid;
}
