using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Input.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runner.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Runner.Headless.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_runner_headless", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runner_headless_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result runner_headless_create([NativeTypeName("ke_scheduler *")] KernelEngine.Scheduler.Native.ke_scheduler* scheduler, [NativeTypeName("ke_input *")] KernelEngine.Input.Native.ke_input* input, [NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_runner_handle *")] KernelEngine.Runner.Native.ke_runner_handle* out_runner);

    [DllImport("ke_runner_headless", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runner_headless_set_log_callback", ExactSpelling = true)]
    public static extern void runner_headless_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_runner_headless", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runner_headless_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* runner_headless_parts([NativeTypeName("size_t *")] nuint* out_count);
}
