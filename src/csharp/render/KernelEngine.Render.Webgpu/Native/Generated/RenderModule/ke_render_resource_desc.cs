using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_resource_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_render_resource_type type;

    public ke_gpu_texture_format format;

    public ke_render_size_mode size_mode;

    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    public float scale_x;

    public float scale_y;
}
