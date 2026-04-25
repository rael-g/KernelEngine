using KernelEngine.Kernel.Native;

namespace KernelEngine.Render.Bgfx.Native;

public unsafe partial struct ke_render_bgfx_params
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;

    [NativeTypeName("struct ke_message_pipe *")]
    public ke_message_pipe* message_pipe;

    [NativeTypeName("struct ke_window *")]
    public ke_window* window;

    [NativeTypeName("const char *")]
    public sbyte* shader_path;

    [NativeTypeName("uint32_t")]
    public uint renderer_type;
}
