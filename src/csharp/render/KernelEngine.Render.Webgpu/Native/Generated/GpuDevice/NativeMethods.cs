using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Async.Native;
using KernelEngine.Completion.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result gpu_device_webgpu_create([NativeTypeName("struct ke_async *")] KernelEngine.Async.Native.ke_async* async, [NativeTypeName("const ke_gpu_device_config *")] global::KernelEngine.Render.GpuDeviceConfig* config, [NativeTypeName("ke_completion **")] KernelEngine.Completion.Native.ke_completion** out_ready, [NativeTypeName("ke_gpu_device_handle *")] KernelEngine.Render.Native.ke_gpu_device_handle* out_device);

    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_set_log_callback", ExactSpelling = true)]
    public static extern void gpu_device_webgpu_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
