using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Window.Glfw.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result window_glfw_create([NativeTypeName("const ke_window_glfw_params *")] ke_window_glfw_params* @params, [NativeTypeName("ke_window **")] KernelEngine.Kernel.Native.ke_window** out_window);
}
