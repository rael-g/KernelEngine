using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_gbuffer_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId mesh_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId world_transform_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId camera_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId frame_cid;

    [NativeTypeName("const char *")]
    public sbyte* output;
}
