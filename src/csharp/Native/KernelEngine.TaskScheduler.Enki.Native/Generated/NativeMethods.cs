using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.TaskScheduler.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_task_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_task_scheduler_enki_create", ExactSpelling = true)]
    public static extern ke_result task_scheduler_enki_create([NativeTypeName("struct ke_allocator *")] ke_allocator* allocator, [NativeTypeName("struct ke_task_scheduler **")] ke_task_scheduler** out_scheduler);
}
