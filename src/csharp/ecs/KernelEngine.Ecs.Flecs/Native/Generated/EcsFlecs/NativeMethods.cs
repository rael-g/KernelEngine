using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Flecs.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_flecs_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result ecs_flecs_create([NativeTypeName("const ke_ecs_flecs_config *")] EcsFlecsConfig* config, [NativeTypeName("ke_ecs_handle *")] KernelEngine.Ecs.Native.ke_ecs_handle* out_ecs);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_flecs_set_log_callback", ExactSpelling = true)]
    public static extern void ecs_flecs_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
