using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Scheduler.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_enki_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_scheduler_handle")]
    public static extern KernelEngine.Scheduler.Native.ke_scheduler_handle scheduler_enki_create([NativeTypeName("struct ke_error **")] ke_error** out_error);
}
