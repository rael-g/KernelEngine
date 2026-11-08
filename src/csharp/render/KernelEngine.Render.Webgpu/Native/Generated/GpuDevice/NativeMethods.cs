using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Configuration.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result gpu_device_webgpu_create([NativeTypeName("struct ke_task_pool *")] KernelEngine.TaskPool.Native.ke_task_pool* task_pool, [NativeTypeName("const ke_gpu_device_webgpu_config *")] ke_gpu_device_webgpu_config* config, [NativeTypeName("ke_gpu_device_handle *")] KernelEngine.Render.Native.ke_gpu_device_handle* out_device);

    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_set_log_callback", ExactSpelling = true)]
    public static extern void gpu_device_webgpu_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
