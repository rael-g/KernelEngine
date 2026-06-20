using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Runtime.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_create", ExactSpelling = true)]
    public static extern ke_runtime_handle runtime_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_scheduler *")] KernelEngine.Scheduler.Native.ke_scheduler* scheduler, [NativeTypeName("const ke_runtime_params *")] ke_runtime_params* @params, ke_error** out_error);
}
