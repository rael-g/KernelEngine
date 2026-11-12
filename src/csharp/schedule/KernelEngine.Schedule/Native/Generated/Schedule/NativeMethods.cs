using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Schedule;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Schedule.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_schedule", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_schedule_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result schedule_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_task_pool *")] KernelEngine.TaskPool.Native.ke_task_pool* task_pool, ke_schedule_handle* out_schedule);

    [DllImport("ke_schedule", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_schedule_set_log_callback", ExactSpelling = true)]
    public static extern void schedule_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
