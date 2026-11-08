using System.Numerics;
using System.Runtime.InteropServices;

using KernelEngine.Configuration.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_render_target_webgpu_window_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result gpu_render_target_webgpu_window_create([NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("struct ke_window *")] KernelEngine.Window.Native.ke_window* window, [NativeTypeName("const ke_gpu_render_target_webgpu_window_config *")] ke_gpu_render_target_webgpu_window_config* config, [NativeTypeName("ke_gpu_render_target_handle *")] KernelEngine.Render.Native.ke_gpu_render_target_handle* out_target);
}
