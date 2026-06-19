using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Scheduler.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_enki_create", ExactSpelling = true)]
    public static extern ke_result scheduler_enki_create([NativeTypeName("struct ke_scheduler_handle *")] KernelEngine.Scheduler.Native.ke_scheduler_handle* out_scheduler, [NativeTypeName("struct ke_error **")] ke_error** out_error);
}
