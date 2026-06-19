using KernelEngine.Common.Native;

namespace KernelEngine.Window.Glfw.Native;

public unsafe partial struct ke_window_glfw_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;

    [NativeTypeName("struct ke_input *")]
    public KernelEngine.Input.Native.ke_input* input;

    [NativeTypeName("const char *")]
    public sbyte* title;

    [NativeTypeName("int32_t")]
    public int width;

    [NativeTypeName("int32_t")]
    public int height;

    public bool fullscreen;
}
