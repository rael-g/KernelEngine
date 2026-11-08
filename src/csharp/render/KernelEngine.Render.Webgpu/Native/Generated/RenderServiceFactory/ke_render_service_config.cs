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

public unsafe partial struct ke_render_service_config
{
    [NativeTypeName("const char *")]
    public sbyte* shader_dir;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat color_format;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat depth_format;

    [NativeTypeName("ke_vec4")]
    public System.Numerics.Vector4 clear_color;
}
