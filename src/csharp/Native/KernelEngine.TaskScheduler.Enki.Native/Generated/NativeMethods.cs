using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.TaskScheduler.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_task_scheduler_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_task_scheduler_enki_create", ExactSpelling = true)]
    public static extern ke_result task_scheduler_enki_create(ke_allocator* allocator, ke_task_scheduler** out_scheduler);
}
