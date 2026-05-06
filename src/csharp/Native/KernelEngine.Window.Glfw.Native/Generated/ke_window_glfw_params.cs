using KernelEngine.Kernel.Native;

namespace KernelEngine.Window.Glfw.Native;

public unsafe partial struct ke_window_glfw_params
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;

    [NativeTypeName("struct ke_input *")]
    public ke_input* input;

    [NativeTypeName("const char *")]
    public sbyte* title;

    [NativeTypeName("int32_t")]
    public int width;

    [NativeTypeName("int32_t")]
    public int height;

    [NativeTypeName("ke_bool")]
    public byte fullscreen;
}
