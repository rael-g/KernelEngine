using KernelEngine.Kernel.Native;

namespace KernelEngine.Text.StbTrueType.Native;

public unsafe partial struct ke_font_stb_params
{
    [NativeTypeName("struct ke_allocator *")]
    public KernelEngine.Kernel.Native.ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Kernel.Native.ke_logger* logger;

    [NativeTypeName("struct ke_render *")]
    public KernelEngine.Kernel.Native.ke_render* render;

    [NativeTypeName("const char *")]
    public sbyte* ttf_path;

    public float pixel_size;

    [NativeTypeName("uint16_t")]
    public ushort atlas_size;

    [NativeTypeName("uint32_t")]
    public uint first_codepoint;

    [NativeTypeName("uint32_t")]
    public uint codepoint_count;
}
