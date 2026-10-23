using System.Runtime.InteropServices;

using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Flecs.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_flecs_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result ecs_flecs_create([NativeTypeName("const ke_ecs_flecs_params *")] ke_ecs_flecs_params* @params, [NativeTypeName("ke_ecs_handle *")] KernelEngine.Ecs.Native.ke_ecs_handle* out_ecs);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_flecs_set_log_callback", ExactSpelling = true)]
    public static extern void ecs_flecs_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
