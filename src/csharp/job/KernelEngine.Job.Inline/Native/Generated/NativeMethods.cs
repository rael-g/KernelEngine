using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Job.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Job.Inline.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_job_system_inline", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_job_system_inline_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result job_system_inline_create([NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_job_system_handle *")] KernelEngine.Job.Native.ke_job_system_handle* out_job_system);

    [DllImport("ke_job_system_inline", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_job_system_inline_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* job_system_inline_parts([NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_job_system_inline", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_job_system_inline_set_log_callback", ExactSpelling = true)]
    public static extern void job_system_inline_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
