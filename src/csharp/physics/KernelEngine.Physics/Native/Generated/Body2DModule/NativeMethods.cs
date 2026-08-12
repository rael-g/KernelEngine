using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Physics.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_body2d_module_create", ExactSpelling = true)]
    public static extern ke_physics_body2d_module_handle physics_body2d_module_create([NativeTypeName("const ke_physics_body2d_module_params *")] ke_physics_body2d_module_params* @params, ke_error** out_error);
}
