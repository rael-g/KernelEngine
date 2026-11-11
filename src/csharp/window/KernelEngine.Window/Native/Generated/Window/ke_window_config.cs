using System.Numerics;

namespace KernelEngine.Window.Native;

public unsafe partial struct ke_window_config
{
    [NativeTypeName("const char *")]
    public sbyte* title;

    [NativeTypeName("int32_t")]
    public int width;

    [NativeTypeName("int32_t")]
    public int height;

    public bool fullscreen;
}
