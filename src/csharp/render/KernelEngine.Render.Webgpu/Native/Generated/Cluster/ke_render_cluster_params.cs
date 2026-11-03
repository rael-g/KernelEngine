using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Configuration.Native;
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

    [NativeTypeName("ke_render_scene_resolve *")]
    public KernelEngine.Render.Native.ke_render_scene_resolve* scene;

    [NativeTypeName("ke_render_frame *")]
    public KernelEngine.Render.Native.ke_render_frame* frame;

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

    [NativeTypeName("ke_configuration *")]
    public KernelEngine.Configuration.Native.ke_configuration* configuration;
}
