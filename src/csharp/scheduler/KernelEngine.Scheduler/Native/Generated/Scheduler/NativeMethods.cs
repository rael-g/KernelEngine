using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Scheduler.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_scheduler", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result scheduler_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_task_pool *")] KernelEngine.TaskPool.Native.ke_task_pool* task_pool, [NativeTypeName("const ke_scheduler_config *")] global::KernelEngine.Scheduler.SchedulerConfig* config, ke_scheduler_handle* out_scheduler);

    [DllImport("ke_scheduler", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scheduler_set_log_callback", ExactSpelling = true)]
    public static extern void scheduler_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
