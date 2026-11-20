using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Async.Native;
using KernelEngine.Completion.Native;
using KernelEngine.Part.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result gpu_device_webgpu_create([NativeTypeName("struct ke_async *")] KernelEngine.Async.Native.ke_async* async, [NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_completion **")] KernelEngine.Completion.Native.ke_completion** out_ready, [NativeTypeName("ke_gpu_device_handle *")] KernelEngine.Render.Native.ke_gpu_device_handle* out_device);

    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_set_log_callback", ExactSpelling = true)]
    public static extern void gpu_device_webgpu_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_gpu_device_webgpu", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_gpu_device_webgpu_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* gpu_device_webgpu_parts([NativeTypeName("size_t *")] nuint* out_count);
}
