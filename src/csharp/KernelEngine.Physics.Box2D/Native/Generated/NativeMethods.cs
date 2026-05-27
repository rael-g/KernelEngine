using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Physics.Box2D.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result physics_2d_box2d_create([NativeTypeName("const ke_physics_2d_box2d_params *")] ke_physics_2d_box2d_params* @params, [NativeTypeName("ke_physics_2d **")] KernelEngine.Kernel.Native.ke_physics_2d** @out);
}
