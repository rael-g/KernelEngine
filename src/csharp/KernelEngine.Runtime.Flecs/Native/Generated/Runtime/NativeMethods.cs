using System.Runtime.InteropServices;

namespace KernelEngine.Runtime.Flecs.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_runtime_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_flecs_create", ExactSpelling = true)]
    public static extern ke_result runtime_flecs_create(ke_allocator* alloc, [NativeTypeName("const ke_runtime_flecs_params *")] ke_runtime_flecs_params* @params, ke_runtime** out_runtime);
}
