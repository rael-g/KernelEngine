using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Glfw.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_create", ExactSpelling = true)]
    public static extern ke_result window_glfw_create([NativeTypeName("const ke_window_glfw_params *")] ke_window_glfw_params* @params, ke_window** out_window);
}
