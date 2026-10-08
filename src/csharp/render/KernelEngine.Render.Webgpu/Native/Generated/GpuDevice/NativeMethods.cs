using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_gpu_device_handle")]
    public static extern KernelEngine.Render.Native.ke_gpu_device_handle gpu_device_webgpu_create([NativeTypeName("const ke_gpu_device_webgpu_params *")] ke_gpu_device_webgpu_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_render_target_webgpu_window_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_gpu_render_target_handle")]
    public static extern KernelEngine.Render.Native.ke_gpu_render_target_handle gpu_render_target_webgpu_window_create([NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("struct ke_window *")] KernelEngine.Window.Native.ke_window* window, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
