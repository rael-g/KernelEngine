using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Job;
using global::KernelEngine.Logger;

using KernelEngine.Job.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Job.Inline.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_job_system_inline", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_job_system_inline_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result job_system_inline_create([NativeTypeName("const ke_job_system_config *")] global::KernelEngine.Job.JobSystemConfig* config, [NativeTypeName("ke_job_system_handle *")] KernelEngine.Job.Native.ke_job_system_handle* out_job_system);

    [DllImport("ke_job_system_inline", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_job_system_inline_set_log_callback", ExactSpelling = true)]
    public static extern void job_system_inline_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
