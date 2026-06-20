using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Window.Glfw.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_window_handle")]
    public static extern KernelEngine.Window.Native.ke_window_handle window_glfw_create([NativeTypeName("const ke_window_glfw_params *")] ke_window_glfw_params* @params, ke_error** out_error);
}
