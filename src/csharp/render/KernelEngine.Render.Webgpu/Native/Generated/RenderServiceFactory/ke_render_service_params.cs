using KernelEngine.Common.Native;

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

    [NativeTypeName("ke_render_resource_binder *")]
    public KernelEngine.Render.Native.ke_render_resource_binder* binder;

    [NativeTypeName("ke_gpu_texture_format")]
    public KernelEngine.Render.Native.ke_gpu_texture_format color_format;

    [NativeTypeName("ke_gpu_texture_format")]
    public KernelEngine.Render.Native.ke_gpu_texture_format depth_format;
}
