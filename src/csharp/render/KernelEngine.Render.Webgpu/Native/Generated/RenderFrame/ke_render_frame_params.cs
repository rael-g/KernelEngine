using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_frame_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_ecs *")]
    public KernelEngine.Ecs.Native.ke_ecs* ecs;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    [NativeTypeName("ke_render_camera *")]
    public KernelEngine.Render.Native.ke_render_camera* camera;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId camera_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId world_transform_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId directional_light_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId ambient_light_cid;
}
