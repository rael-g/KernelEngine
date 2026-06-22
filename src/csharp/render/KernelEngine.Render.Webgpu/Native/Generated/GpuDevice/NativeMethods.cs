using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_create", ExactSpelling = true)]
    public static extern ke_gpu_device_handle gpu_device_webgpu_create([NativeTypeName("const ke_gpu_device_webgpu_params *")] ke_gpu_device_webgpu_params* @params, ke_error** out_error);
}
