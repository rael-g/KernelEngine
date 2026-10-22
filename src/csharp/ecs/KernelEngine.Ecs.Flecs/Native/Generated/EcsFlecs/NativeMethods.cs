using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Flecs.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_flecs_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_ecs_handle")]
    public static extern KernelEngine.Ecs.Native.ke_ecs_handle ecs_flecs_create([NativeTypeName("const ke_ecs_flecs_params *")] ke_ecs_flecs_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_flecs_set_log_callback", ExactSpelling = true)]
    public static extern void ecs_flecs_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
