using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_resource_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("ke_render_resource_type")]
    public global::KernelEngine.Render.RenderResourceType type;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat format;

    [NativeTypeName("ke_render_size_mode")]
    public global::KernelEngine.Render.RenderSizeMode size_mode;

    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    public float scale_x;

    public float scale_y;

    [NativeTypeName("ke_vec4")]
    public System.Numerics.Vector4 clear_value;
}
