using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Scheduler.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_enki_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_scheduler_handle")]
    public static extern KernelEngine.Scheduler.Native.ke_scheduler_handle scheduler_enki_create([NativeTypeName("const ke_scheduler_enki_params *")] ke_scheduler_enki_params* @params, [NativeTypeName("struct ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_enki_set_log_callback", ExactSpelling = true)]
    public static extern void scheduler_enki_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
