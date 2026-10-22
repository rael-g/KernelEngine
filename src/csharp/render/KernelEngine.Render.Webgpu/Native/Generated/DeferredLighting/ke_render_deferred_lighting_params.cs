using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_deferred_lighting_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    public bool ibl_enabled;

    [NativeTypeName("ke_component_id")]
    public uint camera_cid;

    [NativeTypeName("ke_component_id")]
    public uint world_transform_cid;

    [NativeTypeName("ke_component_id")]
    public uint skybox_cid;

    [NativeTypeName("ke_component_id")]
    public uint frame_cid;

    [NativeTypeName("const char *")]
    public sbyte* gbuffer;

    [NativeTypeName("const char *")]
    public sbyte* shadow;

    [NativeTypeName("const char *")]
    public sbyte* clusters;
}
