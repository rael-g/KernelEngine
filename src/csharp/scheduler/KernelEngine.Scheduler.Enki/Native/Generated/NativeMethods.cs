using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Scheduler.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_enki_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result scheduler_enki_create([NativeTypeName("const ke_scheduler_enki_params *")] ke_scheduler_enki_params* @params, [NativeTypeName("ke_scheduler_handle *")] KernelEngine.Scheduler.Native.ke_scheduler_handle* out_scheduler);

    [DllImport("ke_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_enki_set_log_callback", ExactSpelling = true)]
    public static extern void scheduler_enki_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
