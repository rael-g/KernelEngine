using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Runtime;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Runtime.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result runtime_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_task_pool *")] KernelEngine.TaskPool.Native.ke_task_pool* task_pool, [NativeTypeName("const ke_runtime_params *")] ke_runtime_params* @params, ke_runtime_handle* out_runtime);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_set_log_callback", ExactSpelling = true)]
    public static extern void runtime_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
