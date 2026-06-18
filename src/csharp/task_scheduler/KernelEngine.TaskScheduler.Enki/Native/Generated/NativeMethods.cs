using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.TaskScheduler.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_task_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_task_scheduler_enki_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result task_scheduler_enki_create([NativeTypeName("struct ke_task_scheduler_handle *")] ke_task_scheduler_handle* out_scheduler, [NativeTypeName("struct ke_error **")] ke_error** out_error);
}
