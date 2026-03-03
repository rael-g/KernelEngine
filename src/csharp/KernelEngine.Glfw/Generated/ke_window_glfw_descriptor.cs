using KernelEngine.Core.Native;

namespace KernelEngine.Glfw.Native;

public unsafe partial struct ke_window_glfw_descriptor
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;

    [NativeTypeName("struct ke_message_pipe *")]
    public ke_message_pipe* message_pipe;

    public int width;

    public int height;

    [NativeTypeName("const char *")]
    public sbyte* title;
}
