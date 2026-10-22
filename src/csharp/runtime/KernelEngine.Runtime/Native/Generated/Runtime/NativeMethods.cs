using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_create", ExactSpelling = true)]
    public static extern ke_runtime_handle runtime_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_scheduler *")] KernelEngine.Scheduler.Native.ke_scheduler* scheduler, [NativeTypeName("const ke_runtime_params *")] ke_runtime_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_set_log_callback", ExactSpelling = true)]
    public static extern void runtime_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
