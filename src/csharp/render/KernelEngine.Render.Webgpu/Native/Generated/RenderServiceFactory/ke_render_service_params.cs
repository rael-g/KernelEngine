using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_service_params
{
    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("ke_gpu_render_target *")]
    public KernelEngine.Render.Native.ke_gpu_render_target* target;

    [NativeTypeName("ke_ecs *")]
    public KernelEngine.Ecs.Native.ke_ecs* ecs;

    [NativeTypeName("const char *")]
    public sbyte* shader_dir;

    [NativeTypeName("ke_io *")]
    public KernelEngine.Io.Native.ke_io* io;

    [NativeTypeName("ke_render_resource_binder *")]
    public KernelEngine.Render.Native.ke_render_resource_binder* binder;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat color_format;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat depth_format;

    [NativeTypeName("ke_vec4")]
    public System.Numerics.Vector4 clear_color;

    [NativeTypeName("ke_configuration *")]
    public KernelEngine.Configuration.Native.ke_configuration* configuration;
}
