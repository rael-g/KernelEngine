using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.TaskPool.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_task_pool_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_task_pool_enki_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result task_pool_enki_create([NativeTypeName("const ke_task_pool_enki_params *")] ke_task_pool_enki_params* @params, [NativeTypeName("ke_task_pool_handle *")] KernelEngine.TaskPool.Native.ke_task_pool_handle* out_task_pool);

    [DllImport("ke_task_pool_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_task_pool_enki_set_log_callback", ExactSpelling = true)]
    public static extern void task_pool_enki_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
