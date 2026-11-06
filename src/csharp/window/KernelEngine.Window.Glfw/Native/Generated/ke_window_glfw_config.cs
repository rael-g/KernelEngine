using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Input.Native;
using KernelEngine.Result.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Window.Glfw.Native;

public unsafe partial struct ke_window_glfw_config
{
    [NativeTypeName("const char *")]
    public sbyte* title;

    [NativeTypeName("int32_t")]
    public int width;

    [NativeTypeName("int32_t")]
    public int height;

    public bool fullscreen;
}
