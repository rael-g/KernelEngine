using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.View.Native;

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
    public global::KernelEngine.Render.NdcConvention ndc;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId mesh_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId world_transform_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId light_cid;

    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId frame_cid;

    [NativeTypeName("const char *")]
    public sbyte* output;

    [NativeTypeName("uint32_t")]
    public uint resolution;

    public float light_distance;

    public float extent;

    public float near_plane;

    public float far_plane;
}
