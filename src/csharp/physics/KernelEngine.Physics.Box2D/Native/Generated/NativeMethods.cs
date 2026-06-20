using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Physics.Box2D.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_physics_2d_handle")]
    public static extern KernelEngine.Physics.Native.ke_physics_2d_handle physics_2d_box2d_create([NativeTypeName("const ke_physics_2d_box2d_params *")] ke_physics_2d_box2d_params* @params, ke_error** out_error);
}
