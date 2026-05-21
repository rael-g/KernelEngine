using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.TaskScheduler.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_task_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_task_scheduler_enki_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result task_scheduler_enki_create([NativeTypeName("struct ke_allocator *")] KernelEngine.Kernel.Native.ke_allocator* allocator, [NativeTypeName("struct ke_task_scheduler **")] ke_task_scheduler** out_scheduler);
}
