using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Async.Native;
using KernelEngine.Completion.Native;
using KernelEngine.Job.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Scheduler.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_scheduler", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result scheduler_create([NativeTypeName("ke_job_system *")] KernelEngine.Job.Native.ke_job_system* job_system, [NativeTypeName("ke_async *")] KernelEngine.Async.Native.ke_async* async, [NativeTypeName("struct ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, ke_scheduler_handle* out_scheduler);

    [DllImport("ke_scheduler", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_set_log_callback", ExactSpelling = true)]
    public static extern void scheduler_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
