using System.Runtime.InteropServices;

namespace KernelEngine.Ecs.Flecs.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_flecs_create", ExactSpelling = true)]
    public static extern ke_result ecs_flecs_create([NativeTypeName("const ke_ecs_flecs_params *")] ke_ecs_flecs_params* @params, ke_ecs** out_ecs, ke_error** out_error);
}
