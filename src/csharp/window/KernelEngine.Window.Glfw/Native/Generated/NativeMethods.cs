using System.Runtime.InteropServices;

using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Window.Glfw.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result window_glfw_create([NativeTypeName("const ke_window_glfw_params *")] ke_window_glfw_params* @params, [NativeTypeName("ke_window_handle *")] KernelEngine.Window.Native.ke_window_handle* out_window);

    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_set_log_callback", ExactSpelling = true)]
    public static extern void window_glfw_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
