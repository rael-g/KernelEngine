using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Window.Glfw.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_create", ExactSpelling = true)]
    public static extern ke_result window_glfw_create([NativeTypeName("const ke_window_glfw_params *")] ke_window_glfw_params* @params, [NativeTypeName("ke_window_handle *")] KernelEngine.Window.Native.ke_window_handle* out_window, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
