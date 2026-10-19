using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_gpu_device_handle")]
    public static extern KernelEngine.Render.Native.ke_gpu_device_handle gpu_device_webgpu_create([NativeTypeName("const ke_gpu_device_webgpu_params *")] ke_gpu_device_webgpu_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_render_target_webgpu_window_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_gpu_render_target_handle")]
    public static extern KernelEngine.Render.Native.ke_gpu_render_target_handle gpu_render_target_webgpu_window_create([NativeTypeName("const ke_gpu_render_target_webgpu_window_params *")] ke_gpu_render_target_webgpu_window_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
