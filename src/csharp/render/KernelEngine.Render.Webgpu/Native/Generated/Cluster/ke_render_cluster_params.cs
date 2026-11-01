using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_cluster_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("ke_view_space *")]
    public KernelEngine.View.Native.ke_view_space* view_space;

    [NativeTypeName("ke_render_camera *")]
    public KernelEngine.Render.Native.ke_render_camera* camera;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId point_light_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId spot_light_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId world_transform_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId camera_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId frame_cid;

    [NativeTypeName("const char *")]
    public sbyte* output;

    [NativeTypeName("uint32_t")]
    public uint grid_x;

    [NativeTypeName("uint32_t")]
    public uint grid_y;

    [NativeTypeName("uint32_t")]
    public uint grid_z;

    [NativeTypeName("uint32_t")]
    public uint max_lights_per_cluster;
}
