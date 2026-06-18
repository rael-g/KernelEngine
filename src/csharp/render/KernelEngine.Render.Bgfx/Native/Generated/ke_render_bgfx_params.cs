using KernelEngine.Kernel.Native;

namespace KernelEngine.Render.Bgfx.Native;

public unsafe partial struct ke_render_bgfx_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Kernel.Native.ke_logger* logger;

    [NativeTypeName("struct ke_window *")]
    public KernelEngine.Kernel.Native.ke_window* window;

    [NativeTypeName("const char *")]
    public sbyte* shader_path;

    [NativeTypeName("uint32_t")]
    public uint renderer_type;

    public bool vsync;
}
