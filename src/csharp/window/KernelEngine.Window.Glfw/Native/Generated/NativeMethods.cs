using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Window.Glfw.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_window_handle")]
    public static extern KernelEngine.Window.Native.ke_window_handle window_glfw_create([NativeTypeName("const ke_window_glfw_params *")] ke_window_glfw_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_set_log_callback", ExactSpelling = true)]
    public static extern void window_glfw_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
